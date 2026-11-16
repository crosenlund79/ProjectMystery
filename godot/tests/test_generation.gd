## Native case generation (Pilot 4B: scripts/cases/), with no Python.
##
## First the truth-blind investigator's rules on small hand-made cases: what it accepts, and what it refuses - false
## suspicions, evidence out of reach (a refused book, a vehicle behind a closed door, a witness who will not say
## more), misleading and contradicting testimony, two suspects as likely as each other. Then the package format: the
## seal and the relevance verdicts open as the game opens them, the file validates, carries no truth in the view, and
## the same month gives the same bytes (pinned in tests/case_golden.json; the Linux job checks the same pins). Then
## forty months with the whole crime layer (as many as Python's reference): every candidate judged; generation yield
## and the rejection reasons; the sealed suitability report beside Python's (tests/case_reference.json);
## quality concerns; and every case that passes is found by the case library, played, saved, resumed and revealed
## through the game's own investigation engine, with the bundled cases, imported cases and saves left as they were.
extends RefCounted

const CaseGenerate = preload("res://scripts/cases/case_generate.gd")
const CasePackage = preload("res://scripts/cases/case_package.gd")
const CaseSolver = preload("res://scripts/cases/case_solver.gd")
const CaseBuilder = preload("res://scripts/cases/case_builder.gd")
const CaseFormat = preload("res://scripts/core/case_format.gd")
const CaseLibrary = preload("res://scripts/core/case_library.gd")
const SaveStore = preload("res://scripts/core/save_store.gd")
const Investigation = preload("res://scripts/core/investigation.gd")
const Verdict = preload("res://scripts/core/verdict.gd")
const TestSim = preload("res://tests/test_sim.gd")

const SCRIPTS := ["res://scripts/cases/case_suitability.gd", "res://scripts/cases/case_package.gd",
		"res://scripts/cases/case_solver.gd", "res://scripts/cases/case_generate.gd"]
const PROFILES := ["normal", "scarcity", "crisis", "tension"]
const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
const DAYS := 30
const ROOT := "user://test_generation/"
const GOLDEN := "res://tests/case_golden.json"
const REFERENCE := "res://tests/case_reference.json"
## The months whose every package is pinned, byte for byte (the Linux job generates the first of them too).
const GOLDEN_RUNS := [{"seed": 1, "days": 30, "profile": "tension"}, {"seed": 2, "days": 30, "profile": "tension"}]


func run(t, _tree) -> void:
	t.begin("every case-generation script compiles")
	var broken := []
	for path in SCRIPTS:
		var script = load(path)
		if script == null or not script.can_instantiate():
			broken.append(path)
	t.eq(broken, [], "scripts that do not compile")
	t.end()
	if not broken.is_empty():
		return
	_theft_rules(t)
	_assault_rules(t)
	_collision_rules(t)
	_seal(t)
	_determinism(t)
	var months := _survey()
	_yield(t, months)
	_accepted(t, months)
	_rejected(t, months)
	_library(t, months)


static func golden_key(cfg: Dictionary) -> String:
	return "seed %d, %s, %d days, crime" % [cfg["seed"], cfg["profile"], cfg["days"]]


# ================================================================ hand-made cases
const DAY := 1440
const W0 := DAY + 8 * 60  # Day 2 08:00
const W1 := DAY + 20 * 60  # Day 2 20:00


static func _town() -> Dictionary:
	## Five households, a grocery with its ledger, a pub with its tab book, the workshop, the square and Mill Road.
	var people := [["ana", "Ana", "Berg"], ["ben", "Ben", "Cole"], ["cora", "Cora", "Dahl"], ["dan", "Dan", "Eke"],
			["eva", "Eva", "Falk"]]
	var residents := []
	var places := []
	var testimony := {}
	for p in people:
		var home := "home:" + String(p[2]).to_lower()
		residents.append({"id": p[0], "name": "%s %s" % [p[1], p[2]], "first": p[1], "occupation": "mill_hand",
				"age_group": "adult", "household": String(p[2]).to_lower(), "home": home, "condition": "alive",
				"now_at": home})
		places.append({"id": home, "name": "the %s house" % p[2], "kind": "home", "owners": [p[0]], "allowed": true,
				"reply": "Go ahead.", "traces": []})
		testimony[p[0]] = {"goodwill": 3, "style": "nervous", "items": [], "evasive_topics": []}
	for pl in [["grocery", "the grocery", "shop", ["eva"]], ["pub", "the Crooked Pike", "pub", ["dan"]],
			["workshop", "the workshop", "workshop", ["ben"]], ["square", "the square", "square", []],
			["road", "Mill Road", "road", []]]:
		places.append({"id": pl[0], "name": pl[1], "kind": pl[2], "owners": pl[3], "allowed": true, "reply": "",
				"traces": []})
	var mechanisms := []
	for m in ["stolen", "accounting_error", "unresolved"]:
		mechanisms.append({"id": m, "label": m})
	var motives := []
	for m in ["money_trouble", "grudge", "intoxication", "panic", "none", "unknown"]:
		motives.append({"id": m, "label": m})
	return {"schema": "investigation/0.3", "case_id": "fixture", "town": "Testford", "start_time": 2 * DAY + 9 * 60,
			"start_label": "Day 3 09:00", "player_role": "", "residents": residents, "places": places, "vehicles": [],
			"records": {
				"ledger": {"title": "Grocery sales ledger", "place": "grocery", "allowed": true, "reply": "", "entries": []},
				"tabs": {"title": "Bar tab book", "place": "pub", "allowed": true, "reply": "", "entries": []},
				"workshop_orders": {"title": "Workshop job book", "place": "workshop", "allowed": true, "reply": "",
						"entries": []},
			},
			"testimony": testimony, "theory_options": {"mechanisms": mechanisms, "motives": motives},
			"hook": {"title": "The Lighter Savings Tin", "kind": "money_missing", "place": "home:berg",
					"text": "Ana Berg opened the Berg household savings tin on Day 3 and found 300 crowns fewer than there should be.",
					"window": [W0, W1], "window_label": "", "discovered_by": "ana", "recent_from": W0 - 13 * 60},
			"hints": [{"tier": 1, "cost": 1, "text": "A hint."}], "hint_credits": 6}


static func _say(inv: Dictionary, rid: String, key: String, text: String, source: String, time = null, at = null,
		about := [], facts := [], guarded := false, topics := ["window", "whereabouts"]) -> void:
	inv["testimony"][rid]["items"].append({"key": key, "text": text, "topics": topics.duplicate(), "source": source, "time": time,
			"place": at, "about": about, "guarded": guarded, "facts": facts})


static func _fact(who: String, at: String, from: int, to: int) -> Dictionary:
	return {"who": who, "place": at, "from": from, "to": to, "hedged": false}


static func _line(inv: Dictionary, book: String, id: String, time: int, text: String, facts := []) -> void:
	inv["records"][book]["entries"].append({"id": id, "time": time, "text": text, "facts": facts})


static func _solve(inv: Dictionary) -> Dictionary:
	return CaseSolver.new({"format": "project-mystery-case", "format_version": 1, "case_id": "fixture",
			"investigation": inv}).run()


static func _theft() -> Dictionary:
	## Cora says she was at home all day; the ledger has her at the grocery at 11:00; Eva says she is in debt; Dan
	## thinks Ben did it.
	var inv := _town()
	_say(inv, "cora", "K1", "On Day 2, from about 08:00 I was at home.", "self", W0, "home:dahl", [],
			[_fact("cora", "home:dahl", W0, W1)])
	_line(inv, "ledger", "R-ledger#1", DAY + 11 * 60, "Day 2 11:00 sale to Cora Dahl: 3 units, 12 cr",
			[_fact("cora", "grocery", DAY + 11 * 60, DAY + 11 * 60)])
	_say(inv, "eva", "K2", "Cora has been taking food on credit; owes me 30 crowns.", "self", null, null, ["cora"], [],
			false, ["money", "person:cora"])
	for rid in ["dan", "eva", "ana"]:
		_say(inv, rid, "K3" + rid, "If you ask me, Ben had something to do with 300 crowns missing from the Berg household savings tin.",
				"inferred", null, null, ["ben"], [], false, ["incident", "person:ben"])
	return inv


func _theft_rules(t) -> void:
	t.begin("theft: a false account proven by a record or two witnesses, never by rumour or one witness")
	var before: int = Verdict.unseal_count
	var r := _solve(_theft())
	t.check(r["ok"], "a record against Cora's account: %s" % r.get("reason", ""))
	t.eq([r.get("responsible"), r.get("mechanism"), r.get("motive")], ["cora", "stolen", "money_trouble"], "the theft")
	t.check(r.get("cite_refs", []).has("K1") and r.get("cite_refs", []).has("R-ledger#1") and r.get("cite_refs", []).has("K2"),
			"cites the account, the ledger line and the debt: %s" % [r.get("cite_refs")])
	# the record out of reach: the grocer will not show the ledger
	var inv := _theft()
	inv["records"]["ledger"]["allowed"] = false
	inv["records"]["ledger"]["entries"] = []
	r = _solve(inv)
	t.check(not r["ok"], "solved with the ledger refused")
	t.eq(r.get("reason"), "nobody's account of the time in question is proven false", "refused book")
	# one witness against her account: word against word
	inv["testimony"]["ben"]["items"].clear()
	_say(inv, "ben", "K4", "I saw Cora at the square around 11:00 on Day 2.", "saw", DAY + 11 * 60, "square", ["cora"],
			[_fact("cora", "square", DAY + 11 * 60, DAY + 11 * 60)])
	r = _solve(inv)
	t.check(not r["ok"], "one witness was enough")
	t.check(String(r.get("reason", "")).contains("word against word"), "one witness: %s" % r.get("reason"))
	# a second, independent witness: proven
	var two := inv.duplicate(true)
	_say(two, "dan", "K5", "I saw Cora at Mill Road around 13:00 on Day 2, heading toward the Berg house.", "saw",
			DAY + 13 * 60, "road", ["cora"], [_fact("cora", "road", DAY + 13 * 60, DAY + 13 * 60)])
	r = _solve(two)
	t.check(r["ok"] and r.get("responsible") == "cora", "two witnesses: %s" % r.get("reason", ""))
	# ... but the second witness only tells when pressed, and has no patience left: out of reach
	var guarded := two.duplicate(true)
	guarded["testimony"]["dan"]["items"][-1]["guarded"] = true
	guarded["testimony"]["dan"]["goodwill"] = 0
	r = _solve(guarded)
	t.check(not r["ok"], "a guarded statement reached without goodwill")
	guarded["testimony"]["dan"]["goodwill"] = 1
	r = _solve(guarded)
	t.check(r["ok"] and r.get("responsible") == "cora", "pressing a hesitant witness: %s" % r.get("reason", ""))
	# the same witness twice is still one witness
	var same := inv.duplicate(true)
	_say(same, "ben", "K6", "I saw Cora at the square around 14:00 on Day 2.", "saw", DAY + 14 * 60, "square", ["cora"],
			[_fact("cora", "square", DAY + 14 * 60, DAY + 14 * 60)])
	r = _solve(same)
	t.check(not r["ok"], "one witness counted twice")
	# hearsay against an account proves nothing
	var told := inv.duplicate(true)
	_say(told, "dan", "K7", "Ben told me Cora was at the square around 11:00 on Day 2.", "told", DAY + 11 * 60, "square",
			["cora", "ben"], [_fact("cora", "square", DAY + 11 * 60, DAY + 11 * 60)])
	r = _solve(told)
	t.check(not r["ok"], "hearsay counted as a witness")
	# misleading testimony: a mistaken witness against innocent Ben, and rumours about him, while the ledger
	# disproves Cora
	var misled := _theft()
	_say(misled, "ben", "K8", "On Day 2, from about 08:00 I was at the mill.", "self", W0, "home:cole", [],
			[_fact("ben", "home:cole", W0, W1)])
	_say(misled, "dan", "K9", "I saw Ben at the square around 15:00 on Day 2.", "saw", DAY + 15 * 60, "square", ["ben"],
			[_fact("ben", "square", DAY + 15 * 60, DAY + 15 * 60)])
	r = _solve(misled)
	t.eq(r.get("responsible"), "cora", "misled by a mistaken witness or by rumour")
	# two accounts disproved: nothing tells them apart
	var both := misled.duplicate(true)
	_line(both, "tabs", "R-tabs#1", DAY + 16 * 60, "Day 2 16:00 Ben Cole: 1 drink (3 cr)",
			[_fact("ben", "pub", DAY + 16 * 60, DAY + 16 * 60)])
	_say(both, "eva", "K10", "Ben came asking me for money, around 09:00 on Day 2. Times are hard for them.", "self",
			DAY + 9 * 60, null, ["ben"], [], false, ["money", "person:ben"])
	r = _solve(both)
	t.check(not r["ok"], "picked one of two disproved accounts")
	t.eq(r.get("reason"), "more than one account of the time in question is proven false", "two suspects")
	# no motive anyone knows of
	var no_motive := _theft()
	no_motive["testimony"]["eva"]["items"].clear()
	r = _solve(no_motive)
	t.check(not r["ok"], "a thief with no motive")
	# a grudge against the household robbed, when nobody speaks of money trouble
	no_motive["testimony"]["ana"]["items"].append({"key": "K11", "text": "Cora and I have never got on — a broken engagement.",
			"topics": ["conflicts", "person:cora"], "source": "self", "time": null, "place": null, "about": ["cora"],
			"guarded": false, "facts": []})
	r = _solve(no_motive)
	t.eq([r.get("responsible"), r.get("motive")], ["cora", "grudge"], "a grudge")
	t.eq(Verdict.unseal_count, before, "the investigator opened a seal")
	t.end()


static func _assault() -> Dictionary:
	var inv := _town()
	inv["hook"]["kind"] = "person_injured"
	inv["hook"]["place"] = "pub"
	inv["hook"]["text"] = "Ben Cole was hurt in a fight at the Crooked Pike around 21:00 on Day 2: a split lip."
	inv["hook"]["window"] = [DAY + 21 * 60 - 30, DAY + 21 * 60 + 30]
	var mechanisms := []
	for m in ["assaulted", "struck_by_vehicle", "accidental_fall", "unresolved"]:
		mechanisms.append({"id": m, "label": m})
	inv["theory_options"]["mechanisms"] = mechanisms
	var t0 := DAY + 21 * 60
	_say(inv, "ben", "K1", "Dan attacked me at the Crooked Pike around 21:00 on Day 2.", "self", t0, "pub", ["dan"])
	_say(inv, "dan", "K2", "Ben and I came to blows at the Crooked Pike around 21:00 on Day 2. They started it.", "self",
			t0, "pub", ["ben"])
	_say(inv, "cora", "K3", "I saw Dan confront Ben at the Crooked Pike around 20:45 on Day 2 — money owed (40 crowns).",
			"saw", t0 - 15, "pub", ["ben", "dan"])
	return inv


func _assault_rules(t) -> void:
	t.begin("assault: named by someone who was there, and why")
	var r := _solve(_assault())
	t.eq([r.get("responsible"), r.get("mechanism"), r.get("motive")], ["dan", "assaulted", "money_trouble"],
			"the victim names Dan, a quarrel over money (%s)" % r.get("reason", ""))
	var drunk := _assault()
	_line(drunk, "tabs", "R-tabs#1", DAY + 20 * 60, "Day 2 20:00 Dan Eke: 2 drinks (6 cr)",
			[_fact("dan", "pub", DAY + 20 * 60, DAY + 20 * 60)])
	_line(drunk, "tabs", "R-tabs#2", DAY + 20 * 60 + 40, "Day 2 20:40 Dan Eke: 2 drinks (6 cr)",
			[_fact("dan", "pub", DAY + 20 * 60 + 40, DAY + 20 * 60 + 40)])
	r = _solve(drunk)
	t.eq(r.get("motive"), "intoxication", "four drinks on the tab")
	var other := _assault()
	_say(other, "eva", "K4", "I saw Cora attack Ben at the Crooked Pike around 21:00 on Day 2.", "saw", DAY + 21 * 60, "pub",
			["ben", "cora"])
	r = _solve(other)
	t.check(not r["ok"], "two different attackers named, yet a conclusion")
	var rumour := _assault()
	rumour["testimony"]["ben"]["items"].clear()
	_say(rumour, "eva", "K5", "Ben told me Dan attacked them at the Crooked Pike around 21:00 on Day 2.", "told",
			DAY + 21 * 60, "pub", ["ben", "dan"])
	r = _solve(rumour)
	t.check(not r["ok"], "hearsay named the attacker")
	t.end()


static func _collision() -> Dictionary:
	var inv := _town()
	inv["hook"]["kind"] = "property_damaged"
	inv["hook"]["place"] = "road"
	inv["hook"]["text"] = "Eva Falk found the white fence along Mill Road smashed on Day 3, with headlight glass on the verge. Nobody has owned up to it."
	var mechanisms := []
	for m in ["vehicle_collision", "vandalism", "unresolved"]:
		mechanisms.append({"id": m, "label": m})
	inv["theory_options"]["mechanisms"] = mechanisms
	inv["vehicles"] = [{"id": "truck", "name": "the rust-red workshop truck", "kind": "truck", "household": "cole",
			"location": "home:cole", "allowed": true, "reply": "",
			"traces": [{"id": "T-X0001", "description": "The rust-red workshop truck has a dented front bumper, a cracked headlight and flecks of white paint and wood splinters in the grille."}]},
			{"id": "saloon", "name": "the grey saloon car", "kind": "car", "household": "dahl", "location": "home:dahl",
			"allowed": true, "reply": "", "traces": []}]
	_say(inv, "ben", "K1", "The rust-red workshop truck? I hit a deer out on the ridge road a few nights back. Gave me a fright.",
			"self", null, null, ["ben"], [], false, ["vehicles", "person:ben"])
	_say(inv, "cora", "K2", "I saw the grey saloon car hit the fence on Mill Road around 22:15 on Day 2; I think Dan was driving.",
			"saw", DAY + 22 * 60 + 15, "road", ["dan"], [], false, ["window", "vehicles", "incident"])
	return inv


func _collision_rules(t) -> void:
	t.begin("collision: the damaged vehicle and who was tied to it, never a glimpse in the dark")
	var r := _solve(_collision())
	t.eq([r.get("responsible"), r.get("mechanism"), r.get("motive")], ["ben", "vehicle_collision", "panic"],
			"the truck's damage and Ben's deer (%s)" % r.get("reason", ""))
	var shut := _collision()
	shut["vehicles"][0]["allowed"] = false
	shut["vehicles"][0]["traces"] = []
	r = _solve(shut)
	t.check(not r["ok"], "the damage could not be seen, yet a conclusion")
	var earlier := _collision()
	_say(earlier, "eva", "K3", "I saw the rust-red workshop truck with a dented front bumper, a cracked headlight and flecks of white paint and wood splinters in the grille around 09:00 on Day 1.",
			"saw", 9 * 60, "square", [], [], false, ["vehicles"])
	r = _solve(earlier)
	t.check(not r["ok"], "damage seen before the time in question, yet a conclusion")
	var two := _collision()
	two["vehicles"][1]["traces"] = [{"id": "T-X0002", "description": "The grey saloon car has a dented front bumper, a cracked headlight and flecks of white paint and wood splinters in the grille."}]
	r = _solve(two)
	t.check(not r["ok"], "two damaged vehicles, yet a conclusion")
	# damage seen before the time in question, but the workshop mended it before then: the damage now is new
	var mended := earlier.duplicate(true)
	_line(mended, "workshop_orders", "R-workshop_orders#1", 10 * 60, "Day 1 10:00 the rust-red workshop truck (Ben Cole): straightened the front panel, replaced the headlight. Customer said: \"Clipped the fence on Mill Road.\"")
	r = _solve(mended)
	t.eq([r.get("responsible"), r.get("mechanism")], ["ben", "vehicle_collision"], "damage mended before, damaged again (%s)" % r.get("reason", ""))
	# mended parts of another car in the scrap pile, from a repair before the time in question, say nothing of it
	var scrap := _collision()
	scrap["places"][7]["traces"] = [{"id": "T-X0003", "description": "In the workshop scrap pile: a cracked headlight unit and a bent front panel with flecks of white paint, chalked 'the grey saloon car'."}]
	t.eq(scrap["places"][7]["id"], "workshop", "fixture: the workshop")
	r = _solve(scrap)
	t.eq(r.get("responsible"), "ben", "an old scrap pile read as new damage (%s)" % r.get("reason", ""))
	t.end()


# ================================================================ the package
func _seal(t) -> void:
	t.begin("the seal and the relevance verdicts open as the game opens them, whatever the text holds")
	var truth := {"answer": {"responsible": "cora"}, "text": "Ana — the Berg house, “quoted” ✓", "n": 3, "f": 0.25}
	var sealed := CasePackage.seal(truth, "godot-test")
	var opened := CaseFormat.unseal(sealed, "godot-test")
	t.check(opened["ok"], "unseal: %s" % opened.get("error", ""))
	t.eq(opened["truth"]["text"] if opened["ok"] else null, truth["text"], "non-ASCII text survives the seal")
	t.check(not CasePackage.ascii_json(truth).contains("—"), "the sealed JSON is not ASCII")
	t.check(not CaseFormat.unseal(sealed, "godot-other")["ok"], "a seal opened under another case id")
	var pkg := {"case_id": "godot-test", "relevance": CasePackage.seal_relevance({"K0001": {"verdict": "connected",
			"reason": "web"}, "T-X0001": {"verdict": "uncertain", "reason": "untraced"}}, "godot-test")}
	t.eq(CaseFormat.open_relevance(pkg, "K0001"), "connected|web", "relevance verdict")
	t.eq(CaseFormat.open_relevance(pkg, "T-X0001"), "uncertain|untraced", "relevance verdict")
	t.end()


func _determinism(t) -> void:
	t.begin("the same month gives the same case files, byte for byte, and leaves its history as it was")
	var digests := {}
	var pinned_hist = JSON.parse_string(FileAccess.get_file_as_string(TestSim.GOLDEN))
	for cfg in GOLDEN_RUNS:
		var a: Dictionary = CaseGenerate.generate(cfg)
		var b: Dictionary = CaseGenerate.generate(cfg)
		var da := {}
		var db := {}
		for r in a["results"]:
			da[r["case_id"]] = r["package_sha256"]
		for r in b["results"]:
			db[r["case_id"]] = r["package_sha256"]
		t.check(not da.is_empty(), "%s: no candidates" % golden_key(cfg))
		t.eq(db, da, "%s: two generations differ" % golden_key(cfg))
		digests[golden_key(cfg)] = da
		var with_crime: Dictionary = cfg.duplicate()
		with_crime["crime"] = true
		var hk := TestSim.golden_key(with_crime)
		if pinned_hist.has(hk):
			t.eq(a["sim"].events.digest(), pinned_hist[hk], "generating cases changed the pinned history %s" % hk)
	print("  CASE GOLDEN %s" % JSON.stringify(digests, "", true))
	if FileAccess.file_exists(GOLDEN):
		var pinned = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
		for k in digests:
			if pinned.has(k):
				t.eq(digests[k], pinned[k], "the case files of %s differ from the pinned ones" % k)
			else:
				print("  CASE GOLDEN not pinned yet: %s" % k)
	else:
		print("  CASE GOLDEN not pinned yet (no %s)" % GOLDEN)
	t.end()


# ================================================================ forty months
## Forty months; the survey's cases go into a case library of their own (ROOT), never the player's.
func _survey() -> Array:
	var out := []
	var cases_dir := ROOT + "cases/"
	DirAccess.make_dir_recursive_absolute(cases_dir)
	var dir := DirAccess.open(cases_dir)
	if dir != null:
		for f in dir.get_files():
			DirAccess.remove_absolute(cases_dir + f)
	for profile in PROFILES:
		for seed in SEEDS:
			var started := Time.get_ticks_msec()
			var cfg := {"seed": seed, "days": DAYS, "profile": profile}
			var got: Dictionary = CaseGenerate.generate(cfg, cases_dir)
			var accepted := 0
			for r in got["results"]:
				accepted += 1 if r["accepted"] else 0
				print("  GENERATED %-34s %-16s %s: %s" % [r["case_id"], r["family"],
						"ACCEPTED" if r["accepted"] else "rejected [%s]" % r["stage"], r["reason"]])
			print("  generated %s seed %d: %d candidates, %d playable, %d ms" % [profile, seed, got["results"].size(),
					accepted, Time.get_ticks_msec() - started])
			got["cfg"] = cfg
			got.erase("cases")
			out.append(got)
	return out


static func _results(months: Array) -> Array:
	var out := []
	for m in months:
		out.append_array(m["results"])
	return out


func _yield(t, months: Array) -> void:
	t.begin("generation yield: candidates, eligible, solvable and rejected, with the reasons")
	var y: Dictionary = CaseGenerate.yield_report(_results(months), months.size())
	print("  YIELD %d months: %d candidates, %d eligible, %d solvable (playable), %d rejected; %d false accusations" % [
			y["months"], y["candidates"], y["eligible"], y["solvable"], y["rejected"], y["false_accusations"]])
	var fams: Array = y["by_family"].keys()
	fams.sort()
	for f in fams:
		var b: Dictionary = y["by_family"][f]
		print("  YIELD %-17s %3d candidates, %3d eligible, %3d solvable" % [f, b["candidates"], b["eligible"], b["solvable"]])
	for group in ["ineligible", "rejections", "sealed_routes_of_rejected", "concerns"]:
		var keys: Array = y[group].keys()
		keys.sort_custom(func(a, b): return y[group][a] > y[group][b] or (y[group][a] == y[group][b] and a < b))
		for k in keys:
			print("  YIELD %s: %3d  %s" % [group, y[group][k], k])
	# the sealed suitability report (the port of Python's) beside Python's own, for reference
	var mine := CaseGenerate.suitability_stats(_results(months), months.size())
	var ref = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE))
	var theirs: Dictionary = ref.get("suitability", {}) if ref is Dictionary else {}
	t.check(not theirs.is_empty(), "no suitability reference in " + REFERENCE)
	var keys: Array = theirs.keys()
	keys.sort()
	for k in keys:
		print("  suitability-vs-python %-34s godot %8.4f  python %8.4f" % [k, float(mine.get(k, -1.0)), float(theirs[k])])
	t.check(y["solvable"] >= 1, "not one playable case in %d months" % y["months"])
	t.eq(y["false_accusations"], 0, "cases where the truth-blind investigator would accuse an innocent person")
	t.eq(y["candidates"], y["solvable"] + y["rejected"], "every candidate accepted or rejected")
	t.end()


func _accepted(t, months: Array) -> void:
	t.begin("every playable case: the right answer from the player's view, sound support, hints, a whole game")
	var n := 0
	for r in _results(months):
		if not r["accepted"]:
			continue
		n += 1
		var c: Dictionary = r["check"]
		t.check(c["responsible"] and c["mechanism"] and c["motive"] and c["bad"] == 0 and c["good"] >= 1,
				"%s: accepted without a sound conclusion %s" % [r["case_id"], c])
		t.check(r["eligible"], "%s: accepted but not eligible" % r["case_id"])
		t.check(r["path"] != "" and FileAccess.file_exists(r["path"]), "%s: not written" % r["case_id"])
		t.check(String(r["case_id"]).begins_with(CaseBuilder.CASE_ID_PREFIX), "%s: not in the Godot namespace" % r["case_id"])
		var loaded := CaseFormat.load_file(r["path"])
		t.check(loaded["ok"], "%s: the file does not load: %s" % [r["case_id"], loaded["errors"]])
		if not loaded["ok"]:
			continue
		var pkg: Dictionary = loaded["package"]
		t.eq(FileAccess.get_file_as_string(r["path"]).sha256_text(), r["package_sha256"], "%s: file differs" % r["case_id"])
		t.check(_hints_ok(pkg), "%s: hints %s" % [r["case_id"],
				pkg["investigation"].get("hints")])
		t.check(not JSON.stringify(pkg["summary"]).contains(String(r["solver"]["responsible"])),
				"%s: the summary names the culprit" % r["case_id"])
		var game: Dictionary = CaseGenerate.playthrough(r["path"], ROOT)
		t.check(game["ok"], "%s: playthrough: %s" % [r["case_id"], game["problems"]])
		t.eq(game["unsealed_during_play"], 0, "%s: seal opened during play" % r["case_id"])
		t.eq(game["listed_as"], "imported", "%s: listed by the case library" % r["case_id"])
		t.check(int(game["score"]) >= 80, "%s: scored %d" % [r["case_id"], game["score"]])
		var q: Dictionary = r["quality"]
		print("  PLAYABLE %s (%s, %s): %s | route: %s | %d questions, %d pressed | score %d | %d statements, %d%% unrelated%s" % [
				r["case_id"], r["family"], pkg["summary"]["difficulty"], pkg["summary"]["title"],
				", ".join(PackedStringArray(r["solver"]["route"])), r["solver"]["counts"].get("questions", 0),
				r["solver"]["counts"].get("pressed", 0), game["score"], q["statements"], roundi(q["unrelated_share"] * 100),
				("" if q["concerns"].is_empty() else " | CONCERNS: " + "; ".join(PackedStringArray(q["concerns"])))])
		for a in q["idle_alibis"]:
			print("  QUALITY %s: %s's account has them at %s for %d minutes (%s)" % [r["case_id"], a["speaker"], a["place"],
					a["minutes"], "the culprit's lie" if a["lie"] else ("the culprit" if a["responsible"] else "honest")])
	t.check(n >= 1, "no playable case to play")
	t.end()


static func _hints_ok(pkg: Dictionary) -> bool:
	## Hints come in rising tiers, cost what they say, fit the credits, and name only people, places and books in the
	## case.
	var hints: Array = pkg["investigation"]["hints"]
	if hints.is_empty():
		return false
	var spend := 0
	var last := 0
	for h in hints:
		if int(h["tier"]) <= last or int(h["cost"]) != int(h["tier"]):
			return false
		last = int(h["tier"])
		spend += int(h["cost"])
		var text: String = h["text"]
		if text.begins_with("Ask ") or text.begins_with("Compare "):
			var who := text.split(" ")[1].trim_suffix("'s")
			var known := false
			for r in pkg["investigation"]["residents"]:
				known = known or r["first"] == who
			if not known:
				return false
	return spend <= int(pkg["investigation"]["hint_credits"])


func _rejected(t, months: Array) -> void:
	t.begin("rejected cases: accidents, bookkeeping mistakes and owned-up incidents never; the rest with a reason")
	for r in _results(months):
		if r["accepted"]:
			continue
		t.check(String(r["reason"]) != "", "%s: rejected without a reason" % r["case_id"])
		t.check(r["path"] == "", "%s: rejected but written" % r["case_id"])
		if r["family"] in ["accounting_error", "fall"]:
			t.eq(r["stage"], "eligibility", "%s: a %s judged as a case" % [r["case_id"], r["family"]])
			t.check(not r["solver"].get("ok", false), "%s: the investigator accused someone over a %s" % [r["case_id"],
					r["family"]])
		if r["stage"] == "solver":
			t.check(not r["solver"]["ok"], "%s: rejected by the investigator but it concluded" % r["case_id"])
	t.end()


func _library(t, months: Array) -> void:
	t.begin("generated cases sit beside the bundled and imported ones; nothing of the player's is touched")
	var lib = CaseLibrary.new(ROOT)
	var bundled := 0
	var generated := 0
	var ids := {}
	for e in lib.entries:
		t.check(not ids.has(e["case_id"]), "%s listed twice" % e["case_id"])
		ids[e["case_id"]] = true
		if e["source"] == "bundled":
			bundled += 1
			t.check(not String(e["case_id"]).begins_with(CaseBuilder.CASE_ID_PREFIX), "a bundled case in the Godot namespace")
		elif String(e["case_id"]).begins_with(CaseBuilder.CASE_ID_PREFIX):
			generated += 1
	var accepted := 0
	for r in _results(months):
		accepted += 1 if r["accepted"] else 0
	t.eq(generated, accepted, "generated cases in the library")
	t.check(bundled >= 15, "bundled cases: %d" % bundled)
	t.eq(lib.problems, [], "library problems")
	# a bundled case still opens, and a saved game for it survives generating and playing new cases
	var store = SaveStore.new(ROOT)
	var first: Dictionary = {}
	for e in lib.entries:
		if e["source"] == "bundled":
			first = e
			break
	var opened: Dictionary = lib.load_package(first)
	t.check(opened["ok"], "bundled %s does not open" % first.get("case_id"))
	if opened["ok"]:
		var game = Investigation.new(opened["package"])
		game.note("A note made before any case was generated.")
		store.save(game.state)
		var saved_text := FileAccess.get_file_as_string(store.save_path(first["case_id"]))
		var again: Dictionary = CaseGenerate.generate({"seed": 1, "days": DAYS, "profile": "tension"}, ROOT + "cases/")
		for r in again["results"]:
			if r["accepted"]:
				CaseGenerate.playthrough(r["path"], ROOT)
		t.eq(FileAccess.get_file_as_string(store.save_path(first["case_id"])), saved_text, "a bundled case's save changed")
		var resumed = Investigation.new(opened["package"], store.load_state(first["case_id"]))
		t.check(resumed.resumed, "the bundled case's save no longer resumes")
	# importing a generated case from anywhere, as the game's own import does
	for r in _results(months):
		if r["accepted"]:
			var copy := ROOT + "elsewhere/" + CasePackage.file_name(r["case_id"])
			DirAccess.make_dir_recursive_absolute(ROOT + "elsewhere/")
			DirAccess.copy_absolute(r["path"], copy)
			var imp: Dictionary = CaseLibrary.new(ROOT + "import_root/").import_file(copy)
			t.check(imp["ok"], "importing %s: %s" % [r["case_id"], imp["errors"]])
			break
	t.end()
