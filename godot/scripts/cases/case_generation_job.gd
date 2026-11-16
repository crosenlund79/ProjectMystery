## One "Generate Mystery" request from the New Case menu, done a little at a time (no threads).
##
## The screen calls step() once a frame with a small time budget; each call does whole units of work (an hour of the
## town, freezing a candidate, packaging it, questioning one resident, the investigator's conclusion, saving) until
## the budget is spent, so the progress bar keeps moving and Cancel takes effect between units. Nothing is written
## before the very end, and then atomically, so a cancelled or failed request leaves no trace.
##
## A request tries towns (attempts) one seed after another: the chosen seed first, then the next ones; or, with no
## seed given, a random one and the next ones. In each town it judges every case candidate as soon as the
## investigator would arrive, exactly as case_generate.gd does (the same packaging, the same truth-blind
## investigator, the same check against the sealed truth afterwards), and stops at the first that passes. Only that
## case is saved, into the player's case folder, where the case library lists it. The town is not simulated further
## than needed: the case is frozen at its case start, so it is the same as a whole run would give.
##
## Progress is neutral: the attempt, the seed, the day, how many possible cases have been looked at and what is being
## done. Never who did it, what happened, which incidents there were or any sealed evidence.
extends RefCounted

const Simulation = preload("res://scripts/sim/simulation.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Incidents = preload("res://scripts/sim/sim_incidents.gd")
const CaseBuilder = preload("res://scripts/cases/case_builder.gd")
const CaseGenerate = preload("res://scripts/cases/case_generate.gd")
const CasePackage = preload("res://scripts/cases/case_package.gd")
const CaseFormat = preload("res://scripts/core/case_format.gd")

const DAY := 1440
const SIZES := [8, 10, 12]
const PROFILES := ["normal", "scarcity", "crisis", "tension"]
const DEFAULT_DAYS := 60
const MIN_DAYS := 14
const MAX_DAYS := 120
const DEFAULT_ATTEMPTS := 12
const MAX_ATTEMPTS := 40
const MAX_SEED := 999999

# ---- the request
var residents := 10
var profile := "normal"
var days := DEFAULT_DAYS
var first_seed := 1
var seed_chosen := false  # the player gave the seed (rather than a random one)
var max_attempts := DEFAULT_ATTEMPTS
var library_dir := "user://cases/"
var exclude := {}  # case ids not to offer (already in the library, for "Generate Another")

# ---- progress, safe to show
var status := "running"  # running | found | failed | cancelled | error
var attempt := 0
var town_seed := 0
var day := 0
var phase := ""  # simulating | checking | saving
var detail := ""
var checked := 0  # possible cases looked at in this request
var result := {}  # when found: the spoiler-free card of the case and where it is
var error_message := ""
var steps := 0
var longest_step_ms := 0

# ---- internals
var _sim = null
var _end := 0
var _pending := []  # cases frozen at their case start, waiting to be judged
var _judging := {}  # the case being judged: {st, stage, index}


static func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, MAX_SEED)


static func problem(residents_: int, profile_: String, days_: int, seed_, attempts_: int) -> String:
	## Why a request cannot be made, in the player's words, or "".
	if not (residents_ in SIZES):
		return "The town must have 8, 10 or 12 residents."
	if not (profile_ in PROFILES):
		return "Choose the conditions: normal, scarcity, crisis or tension."
	if days_ < MIN_DAYS or days_ > MAX_DAYS:
		return "The simulation must run between %d and %d days." % [MIN_DAYS, MAX_DAYS]
	if seed_ != null and (int(seed_) < 1 or int(seed_) > MAX_SEED):
		return "The seed must be a whole number from 1 to %d." % MAX_SEED
	if attempts_ < 1 or attempts_ > MAX_ATTEMPTS:
		return "Try between 1 and %d towns." % MAX_ATTEMPTS
	return ""


func _init(settings: Dictionary) -> void:
	## settings: residents, profile, days, seed (int, or null for a random one), attempts, library_dir, exclude.
	residents = int(settings.get("residents", 10))
	profile = String(settings.get("profile", "normal"))
	days = int(settings.get("days", DEFAULT_DAYS))
	max_attempts = int(settings.get("attempts", DEFAULT_ATTEMPTS))
	library_dir = String(settings.get("library_dir", "user://cases/"))
	if not library_dir.ends_with("/"):
		library_dir += "/"
	for id in settings.get("exclude", []):
		exclude[id] = true
	var given = settings.get("seed")
	seed_chosen = given != null
	first_seed = int(given) if given != null else random_seed()
	var p := problem(residents, profile, days, given, max_attempts)
	if p != "":
		status = "error"
		error_message = p


func config() -> Dictionary:
	return {"seed": town_seed, "days": days, "profile": profile, "residents": residents, "crime": true}


func seed_for(attempt_number: int) -> int:
	## Attempt 1 uses the first seed, attempt 2 the next, and so on (wrapping round after the largest seed).
	return (first_seed - 1 + attempt_number - 1) % MAX_SEED + 1


func running() -> bool:
	return status == "running"


func cancel() -> void:
	## Takes effect at once: no further work is done, and nothing has been written.
	if running():
		status = "cancelled"
		_sim = null
		_pending.clear()
		_judging = {}


func progress() -> float:
	## How far through the current town's days (0..1).
	return clampf(float(day) / float(maxi(1, days)), 0.0, 1.0)


func step(budget_ms := 12) -> void:
	## Whole units of work until the budget is spent (at least one).
	var start := Time.get_ticks_msec()
	while running():
		var t0 := Time.get_ticks_msec()
		_unit()
		steps += 1
		longest_step_ms = maxi(longest_step_ms, Time.get_ticks_msec() - t0)
		if Time.get_ticks_msec() - start >= budget_ms:
			break


func run_to_end() -> void:
	## For tests and tools: the whole request at once.
	while running():
		step(1000000)


# ================================================================ one unit of work
func _unit() -> void:
	if not _judging.is_empty():
		_judge_unit()
	elif not _pending.is_empty():
		_next_candidate()
	elif _sim != null and _sim.t < _end:
		_sim.step()
		day = mini(days, int(_sim.t / DAY))
		phase = "simulating"
		detail = "Day %d of %d" % [day, days]
		for inc in _sim.incidents:
			if inc["case_start"] == _sim.t and Incidents.is_candidate(inc):
				# frozen at this instant, as the investigator arrives; judged next
				_pending.append(CaseBuilder.new(_sim, inc).build())
	else:
		_next_town()


func _next_town() -> void:
	_sim = null
	if attempt >= max_attempts:
		status = "failed"
		phase = ""
		detail = ""
		return
	attempt += 1
	town_seed = seed_for(attempt)
	day = 0
	phase = "simulating"
	detail = "Day 0 of %d" % days
	var sim = Simulation.new(config())
	if not sim.ok:
		status = "error"
		error_message = "The town could not be set up: %s" % [sim.errors]
		return
	_sim = sim
	_end = days * DAY


func _next_candidate() -> void:
	var case_: Dictionary = _pending.pop_front()
	checked += 1
	phase = "checking"
	if not case_["eligibility"]["eligible"] or exclude.has(case_["case_id"]):
		detail = "Looking at a possible case"
		return
	detail = "Writing up a possible case"
	var st := CaseGenerate.judge_begin(case_, "", false)
	if st["done"]:
		return
	_judging = {"st": st, "stage": "gather", "index": 0}


func _judge_unit() -> void:
	var st: Dictionary = _judging["st"]
	var solver = st["solver"]
	var people: Array = solver.data["residents"]
	match String(_judging["stage"]):
		"gather":
			var i: int = _judging["index"]
			if i < people.size():
				detail = "Testing the case: questioning residents (%d of %d)" % [i + 1, people.size()]
				solver.gather_resident(people[i])
				_judging["index"] = i + 1
			else:
				detail = "Testing the case: places, vehicles and records"
				solver.gather_world()
				_judging["stage"] = "conclude"
		"conclude":
			detail = "Testing the case: can it be solved from the evidence?"
			var r: Dictionary = CaseGenerate.judge_end(st, "")
			if r["accepted"]:
				_judging["stage"] = "save"
				_judging["r"] = r
			else:
				_judging = {}
		"save":
			phase = "saving"
			detail = "Saving the case"
			_save(st, _judging["r"])
			_judging = {}


func _save(st: Dictionary, r: Dictionary) -> void:
	## Into the case folder, never over a different file of the same name; the same case already there is offered as
	## it is, and the file is written whole or not at all.
	var pkg: Dictionary = st["pkg"]
	var case_id: String = pkg["case_id"]
	var text: String = st["text"]
	var path := library_dir + CasePackage.file_name(case_id)
	var existed := false
	if FileAccess.file_exists(path):
		if FileAccess.get_sha256(path) != r["package_sha256"]:
			# a different file under this name (made by another version): keep it, and look further
			exclude[case_id] = true
			detail = "A different version of this case is already saved; looking further"
			return
		existed = true
	elif not write_atomic(path, text):
		status = "error"
		error_message = "The case could not be saved in %s." % ProjectSettings.globalize_path(library_dir)
		return
	var s: Dictionary = pkg["summary"]
	result = {"case_id": case_id, "path": path, "existed": existed, "title": s["title"], "town": s["town"],
			"season": s["season"], "difficulty": s["difficulty"], "start_label": s["start_label"], "seed": town_seed,
			"residents": residents, "days": days, "profile": profile, "attempt": attempt,
			"package_sha256": r["package_sha256"]}
	status = "found"
	phase = "saving"
	detail = "Saved"


static func write_atomic(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".part"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if FileAccess.get_sha256(tmp) != text.sha256_text():
		DirAccess.remove_absolute(tmp)
		return false
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true
