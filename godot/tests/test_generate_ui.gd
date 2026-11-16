## New Case > Generate Mystery, through the real interface: the form, the generation screen and what it shows (and
## never shows), cancelling, a town with no fair mystery (Retry, Back), a case found and saved, the same seed asked
## for twice, Generate Another, opening the generated case from the library, investigating it, saving, a restart,
## and the reveal. Bundled cases, an imported case and an investigation saved before any generation are untouched.
extends RefCounted

const Verdict = preload("res://scripts/core/verdict.gd")
const CaseFormat = preload("res://scripts/core/case_format.gd")
const CaseSolver = preload("res://scripts/cases/case_solver.gd")
const CaseGenerate = preload("res://scripts/cases/case_generate.gd")
const Job = preload("res://scripts/cases/case_generation_job.gd")

const ROOT := "user://test_generate_ui/"
const CHECK_ROOT := "user://test_generate_ui_check/"
const GOLDEN := "res://tests/case_golden.json"
## A month whose packages are pinned (tests/case_golden.json): its first playable case is known byte for byte.
const SEED := 2
const PROFILE := "tension"
const DAYS := 30
const FIRST := "godot-2-tension-30d-r10-I1"
const SECOND := "godot-2-tension-30d-r10-I2"

var t
var tree: SceneTree
var main


func run(t_, tree_: SceneTree) -> void:
	t = t_
	tree = tree_
	_job_rules()
	await _start_game()
	var before := await _before()
	await _form()
	await _cancel()
	await _failure()
	var culprit := await _generate()
	await _duplicate_seed()
	await _another()
	await _investigate(culprit)
	await _restart_and_reveal(before)
	main.queue_free()
	await _frames(1)


# ================================================================ helpers
func _start_game() -> void:
	# a clean player folder: no cases of its own, no saves
	_clear_dir(ROOT + "cases/")
	main = load("res://scenes/main.tscn").instantiate()
	main.user_root = ROOT
	tree.root.add_child(main)
	_resize(Vector2(960, 640))
	await _frames(2)
	main.saves.reset_all()
	main.change_setting("intro_seen", true)
	main.show_main_menu()
	await _frames(1)


static func _clear_dir(dir_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir_path)
	var d := DirAccess.open(dir_path)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(dir_path + f)


func _resize(to: Vector2) -> void:
	main.anchor_right = 0.0
	main.anchor_bottom = 0.0
	main.position = Vector2.ZERO
	main.size = to


func _find(node_name: String):
	return main.find_child(node_name, true, false)


func _frames(n: int) -> void:
	for i in range(n):
		await tree.process_frame


func _press(node_name: String) -> void:
	var b = _find(node_name)
	t.check(b != null, "button %s not found on screen '%s'" % [node_name, main.current])
	if b != null:
		b.pressed.emit()
	await _frames(1)


func _set_form(residents: int, profile: String, days: int, seed_text: String, attempts: int) -> void:
	var size_opt: OptionButton = _find("TownSize")
	size_opt.select(Job.SIZES.find(residents))
	var cond: OptionButton = _find("Conditions")
	cond.select(Job.PROFILES.find(profile))
	cond.item_selected.emit(cond.selected)
	(_find("Days") as SpinBox).value = days
	(_find("Seed") as LineEdit).text = seed_text
	(_find("Attempts") as SpinBox).value = attempts


func _screen():
	return main.screen


func _labels(node: Node, out: Array) -> void:
	if node is Label:
		out.append(String(node.text))
	elif node is Button:
		out.append(String(node.text))
	for c in node.get_children():
		_labels(c, out)


func _layout_ok(where: String) -> void:
	## Nothing on the screen runs off its right edge or collapses (the same rule as the end-to-end test).
	await _frames(2)
	var problems := []
	_walk(main.screen, main.size, problems)
	t.check(problems.is_empty(), "layout on %s: %s" % [where, "; ".join(PackedStringArray(problems.slice(0, 4)))])


func _walk(node: Node, view: Vector2, problems: Array) -> void:
	if node is Window:
		return
	if node is Control:
		var c: Control = node as Control
		if not c.is_visible_in_tree():
			return
		var r := c.get_global_rect()
		if c is BaseButton and (r.size.x < 16 or r.size.y < 16):
			problems.append("%s collapsed" % c.name)
		if r.end.x > view.x + 2:
			problems.append("%s runs off the right edge" % c.name)
		if c is Label and (c as Label).text.length() > 12 and r.size.x < 80:
			problems.append("%s squeezed" % c.name)
	for ch in node.get_children():
		_walk(ch, view, problems)


func _wait(max_frames := 20000) -> Dictionary:
	## Let the generation run, frame by frame, as the game does. Returns what was seen meanwhile.
	var seen := {"frames": 0, "bars": [], "texts": [], "engine_seen": false, "town_map_seen": false}
	var scr = _screen()
	var job = scr.job
	while scr.view == "running" and seen["frames"] < max_frames:
		await tree.process_frame
		seen["frames"] += 1
		if main.engine != null:
			seen["engine_seen"] = true
		if main.find_child("TownMap", true, false) != null:
			seen["town_map_seen"] = true
		if scr.view == "running" and seen["frames"] % 5 == 1:
			seen["bars"].append([int(scr.job.attempt), float(_find("GenerateProgress").value)])
			_labels(scr, seen["texts"])
	if job != null:
		print("  GENERATE UI request (seed %d, %s, %d residents, %d days): %s after %d town(s), %d units of work over %d frames, longest unit %d ms" % [
				job.first_seed, job.profile, job.residents, job.days, job.status, job.attempt, job.steps, seen["frames"],
				job.longest_step_ms])
	return seen


func _user_cases() -> Array:
	var out := []
	var d := DirAccess.open(ROOT + "cases/")
	if d != null:
		for f in d.get_files():
			out.append(f)
	out.sort()
	return out


# ================================================================ the request itself
func _job_rules() -> void:
	t.begin("a generation request: its settings, a random seed, and never over a different file")
	var random_job = Job.new({"residents": 10, "profile": "normal", "days": 60, "seed": null})
	t.check(random_job.running() and not random_job.seed_chosen, "a request without a seed")
	t.check(random_job.first_seed >= 1 and random_job.first_seed <= Job.MAX_SEED, "random seed out of range")
	for bad in [{"residents": 9}, {"profile": "summer"}, {"days": 5}, {"days": 500}, {"seed": 0}, {"attempts": 0}]:
		var s := {"residents": 10, "profile": "normal", "days": 60, "seed": 1, "attempts": 3}
		s.merge(bad, true)
		var j = Job.new(s)
		t.check(not j.running() and j.error_message != "", "accepted %s" % [bad])
	var last = Job.new({"seed": Job.MAX_SEED, "attempts": 3})
	t.eq([last.seed_for(1), last.seed_for(2)], [Job.MAX_SEED, 1], "seeds after the largest")
	# a different file already under the name of the first case: kept as it is, and the next case offered instead
	var dir := ROOT + "other_version/"
	_clear_dir(dir)
	var stale := dir + FIRST + ".mcase"
	var f := FileAccess.open(stale, FileAccess.WRITE)
	f.store_string("{\"made by\": \"another version\"}\n")
	f.close()
	var stale_sha := FileAccess.get_sha256(stale)
	var job = Job.new({"residents": 10, "profile": PROFILE, "days": DAYS, "seed": SEED, "attempts": 1, "library_dir": dir})
	job.run_to_end()
	t.eq(String(job.status), "found", "nothing found beside the other version (%s)" % job.error_message)
	t.eq(job.result.get("case_id"), SECOND, "the next case of the town")
	t.eq(FileAccess.get_sha256(stale), stale_sha, "a different file of the same name was overwritten")
	var leftovers := []
	var d := DirAccess.open(dir)
	for name in d.get_files():
		if name.ends_with(".part"):
			leftovers.append(name)
	t.eq(leftovers, [], "partial files left behind")
	t.end()


# ================================================================ before anything is generated
func _before() -> Dictionary:
	## An investigation in a bundled case and an imported case, made before any generation.
	t.begin("before generating: a bundled case in progress and an imported case")
	var bundled: Dictionary = main.library.entries[0]
	main.open_case(bundled, true)
	await _frames(1)
	main.engine.note("Made before any mystery was generated.")
	main.show_main_menu()  # saves it, as leaving a case does
	await _frames(1)
	var save_text := FileAccess.get_file_as_string(main.saves.save_path(bundled["case_id"]))
	t.check(save_text.contains("Made before any mystery was generated."), "the bundled case was not saved")
	var folder := ProjectSettings.globalize_path("res://") + "../import-test-cases/"
	var imported := ""
	var d := DirAccess.open(folder)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".mcase"):
				var r: Dictionary = main.library.import_file(folder + f)
				t.check(r["ok"], "import: %s" % [r["errors"]])
				imported = r["case_id"]
				break
	t.check(imported != "", "no import-test case to import")
	t.end()
	return {"bundled": bundled["case_id"], "save": save_text, "imported": imported, "count": main.library.entries.size()}


# ================================================================ the form
func _form() -> void:
	t.begin("New Case > Generate Mystery: the settings, with their defaults")
	await _press("NewCaseButton")
	t.eq(main.current, "new_case", "New Case")
	t.check(_find("DifficultyFilter") != null and _find("ModeOption") != null, "the difficulty and mode choices are gone")
	await _press("GenerateMysteryButton")
	t.eq(main.current, "generate", "the Generate Mystery screen")
	t.eq(main.engine, null, "an investigation is still open while generating")
	t.eq((_find("TownSize") as OptionButton).selected, 1, "default town size is not 10")
	t.eq((_find("TownSize") as OptionButton).get_item_text(1), "10 residents", "town size")
	t.eq((_find("TownSize") as OptionButton).item_count, 3, "8, 10 or 12 residents")
	t.eq((_find("Conditions") as OptionButton).item_count, 4, "normal, scarcity, crisis, tension")
	t.eq(int((_find("Days") as SpinBox).value), 60, "default simulation length")
	t.eq((_find("Seed") as LineEdit).text, "", "the seed is optional (random when empty)")
	t.eq(int((_find("Attempts") as SpinBox).value), Job.DEFAULT_ATTEMPTS, "default attempts")
	await _layout_ok("Generate Mystery form")
	# an invalid seed is refused before anything runs
	_set_form(10, "normal", 60, "twelve", 3)
	await _press("GenerateButton")
	t.eq(_screen().view, "form", "an invalid seed started a generation")
	var note = _find("GenerateNote")
	t.check(note != null and String(note.text).contains("seed"), "no explanation of the invalid seed")
	# Esc and Back return to New Case
	await _press("GenerateBackButton")
	t.eq(main.current, "new_case", "Back did not return to New Case")
	t.end()


# ================================================================ cancelling
func _cancel() -> void:
	t.begin("cancelling: at once, between batches of work, and nothing is saved")
	await _press("GenerateMysteryButton")
	var files_before := _user_cases()
	_set_form(12, "normal", 60, "5", 3)
	await _press("GenerateButton")
	var scr = _screen()
	t.eq(scr.view, "running", "generation did not start")
	await _frames(8)
	var job = scr.job
	t.check(job.running(), "the generation finished before it could be cancelled")
	var day_then: int = job.day
	t.check(_find("CancelGenerateButton") != null, "no Cancel button")
	await _press("CancelGenerateButton")
	t.eq(scr.view, "form", "Cancel did not return to the settings")
	t.eq(String(job.status), "cancelled", "the job was not cancelled")
	await _frames(10)
	t.eq(job.day, day_then, "work went on after Cancel")
	t.eq(_user_cases(), files_before, "files were written by a cancelled generation")
	var note = _find("GenerateNote")
	t.check(note != null and String(note.text).contains("Nothing was saved"), "no word that nothing was saved")
	t.eq(int((_find("TownSize") as OptionButton).selected), 2, "the settings were lost on cancelling")
	t.end()


# ================================================================ no fair mystery
func _failure() -> void:
	t.begin("a town with no fair mystery: the reason, then Retry with the next towns, or Back")
	_set_form(10, "normal", 14, "5", 1)
	await _press("GenerateButton")
	var scr = _screen()
	var seen := await _wait()
	t.eq(scr.view, "failed", "a two-week normal town gave a mystery (or the generation never ended)")
	t.check(_find("FailedTitle") != null, "no failure message")
	t.check(_find("RetryButton") != null and _find("FailedBackButton") != null, "no Retry or Back")
	t.eq(_user_cases().filter(func(f): return String(f).begins_with("godot-")), [], "a failed generation saved a case")
	t.check(seen["frames"] >= 2, "the generation did not show its progress")
	await _layout_ok("no mystery found")
	await _press("RetryButton")
	t.eq(scr.view, "running", "Retry did not start again")
	t.eq(int(scr.job.first_seed), 6, "Retry did not move on to the next town")
	await _wait()
	t.check(scr.view in ["failed", "found"], "the retry did not end")
	if scr.view == "found":
		# a fair mystery in the next town after all: fine, but then it must be in the library
		t.check(not main.library.find(scr.job.result["case_id"]).is_empty(), "a found case is not in the library")
		await _press("CaseLibraryButton")
		await _press("GenerateMysteryButton")
	else:
		await _press("FailedBackButton")
	t.eq(_screen().view, "form", "Back did not return to the settings")
	t.end()


# ================================================================ a mystery found
func _generate() -> String:
	t.begin("a mystery found, judged without the truth, saved and listed; nothing given away meanwhile")
	var sealed_before: int = Verdict.unseal_count
	_set_form(10, PROFILE, DAYS, str(SEED), 4)
	await _press("GenerateButton")
	var scr = _screen()
	var started := Time.get_ticks_msec()
	var seen := await _wait()
	var ms := Time.get_ticks_msec() - started
	t.eq(scr.view, "found", "no mystery found in seed 2, tension (status %s: %s)" % [scr.job.status, scr.job.error_message])
	if scr.view != "found":
		t.end()
		return ""
	var job = scr.job
	print("  GENERATE UI seed %d %s %d days: %s in %d ms over %d frames; longest unit of work %d ms; %d units" % [SEED,
			PROFILE, DAYS, job.result["case_id"], ms, seen["frames"], job.longest_step_ms, job.steps])
	t.eq(job.result["case_id"], FIRST, "the first playable case of the town")
	t.eq(Verdict.unseal_count, sealed_before, "a case was revealed while generating")
	# no concurrent gameplay
	t.check(not seen["engine_seen"] and not seen["town_map_seen"], "an investigation was open during generation")
	t.check(seen["frames"] >= 2 and job.steps > seen["frames"], "the work was not spread over frames (%d frames, %d units)"
			% [seen["frames"], job.steps])
	t.check(job.longest_step_ms < 2000, "the screen froze for %d ms" % job.longest_step_ms)
	# the bar shows the town's days, rising
	var last := -1.0
	var rising := true
	for b in seen["bars"]:
		if b[1] + 0.001 < last:
			rising = false
		last = b[1]
	t.check(rising and last > 0, "the progress bar did not show the days passing: %s" % [seen["bars"].slice(0, 8)])
	# never anything sealed: the culprit, the motive, what happened
	var opened := CaseFormat.unseal(CaseFormat.load_file(job.result["path"])["package"]["sealed_truth"], FIRST)
	var truth: Dictionary = opened["truth"]
	var culprit: String = truth["answer"]["responsible"]
	var names := [truth["private_states"][culprit]["name"], String(truth["private_states"][culprit]["name"]).get_slice(" ", 0)]
	var shown: Array = seen["texts"].duplicate()
	_labels(scr, shown)
	var leaked := []
	for text in shown:
		for n in names + [truth["narrative"], "responsible", "culprit", "motive"]:
			if String(text).contains(String(n)) and not leaked.has(n):
				leaked.append(n)
	t.eq(leaked, [], "the generation screens gave away the case")
	# saved, byte for byte the pinned package of this month, and listed beside the other cases
	var pinned = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	t.eq(FileAccess.get_sha256(job.result["path"]), pinned["seed 2, tension, 30 days, crime"][FIRST],
			"the saved case differs from the pinned package of seed 2, tension (not reproducible)")
	t.eq(job.result["package_sha256"], FileAccess.get_sha256(job.result["path"]), "what was judged is not what was saved")
	t.eq(_user_cases().filter(func(f): return String(f).ends_with(".part")), [], "a partial file was left behind")
	var e: Dictionary = main.library.find(FIRST)
	t.check(not e.is_empty(), "the case library does not list the new case")
	t.eq(e.get("source"), "generated", "the new case is not listed as generated")
	t.eq([e.get("seed"), e.get("residents"), e.get("days")], [SEED, 10, DAYS], "how the town was made")
	t.check(_find("InvestigateButton") != null and _find("GenerateAnotherButton") != null
			and _find("CaseLibraryButton") != null, "Investigate, Generate Another, Case Library")
	await _layout_ok("a mystery is ready")
	# the same case, judged again in another folder: a fair mystery, truly
	var game: Dictionary = CaseGenerate.playthrough(job.result["path"], CHECK_ROOT)
	t.check(game["ok"] and int(game["score"]) >= 80, "the saved case does not hold up: %s" % [game["problems"]])
	# listed in the case library
	await _press("CaseLibraryButton")
	t.eq(main.current, "new_case", "Case Library did not show the cases")
	t.check(_find("StartCase_" + FIRST) != null, "the new case is not in the case list")
	t.check(_find("Generated_" + FIRST) != null, "the new case is not marked as generated")
	t.end()
	return culprit


func _duplicate_seed() -> void:
	t.begin("the same seed again: the same mystery, not written twice, not overwritten")
	var count: int = main.library.entries.size()
	var path: String = main.library.user_cases + FIRST + ".mcase"
	var mtime := FileAccess.get_modified_time(path)
	var sha := FileAccess.get_sha256(path)
	await _press("GenerateMysteryButton")
	t.eq((_find("Seed") as LineEdit).text, str(SEED), "the settings were not kept")
	await _press("GenerateButton")
	var scr = _screen()
	await _wait()
	t.eq(scr.view, "found", "the same seed did not find its mystery again")
	t.eq(scr.job.result.get("case_id"), FIRST, "the same seed gave another case")
	t.check(scr.job.result.get("existed", false), "the existing case was not recognised")
	t.check(String(_find("FoundTitle").text).contains("already"), "the player is not told it is already there")
	t.eq(FileAccess.get_sha256(path), sha, "the case file changed")
	t.eq(FileAccess.get_modified_time(path), mtime, "the case file was written again")
	t.eq(main.library.entries.size(), count, "a duplicate entry in the case library")
	t.end()


func _another() -> void:
	t.begin("Generate Another: a different mystery, the case already there not offered again")
	var count: int = main.library.entries.size()
	await _press("GenerateAnotherButton")
	var scr = _screen()
	await _wait()
	t.eq(scr.view, "found", "Generate Another found nothing (status %s)" % scr.job.status)
	if scr.view == "found":
		t.eq(scr.job.result["case_id"], SECOND, "the next mystery of the same town")
		t.check(not scr.job.result["existed"], "Generate Another offered a case already in the library")
		t.eq(main.library.entries.size(), count + 1, "the new case is not listed")
		var pinned = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
		t.eq(FileAccess.get_sha256(scr.job.result["path"]), pinned["seed 2, tension, 30 days, crime"][SECOND],
				"the second case differs from its pinned package")
	t.end()


# ================================================================ investigating it
func _investigate(culprit: String) -> void:
	t.begin("Investigate: the generated case opens in the game, with the chosen detective mode, and saves")
	await _press("CaseLibraryButton")
	var mode_opt = _find("ModeOption")
	mode_opt.select(2)
	mode_opt.item_selected.emit(2)
	await _frames(1)
	await _press("GenerateMysteryButton")
	await _press("GenerateButton")
	await _wait()
	t.eq(_screen().view, "found", "the case was not found again")
	var sealed_before: int = Verdict.unseal_count
	await _press("InvestigateButton")
	t.eq(main.current, "investigation", "Investigate did not open the case")
	if main.current != "investigation":
		t.end()
		return
	t.eq(main.engine.case_id, FIRST, "another case opened")
	t.eq(main.engine.mode(), "experienced", "the detective mode chosen on New Case was not used")
	var scr = main.screen
	# a little by hand, through the town: walk to someone, talk, ask
	for p in scr.town.places():
		if not scr.town.people_at(p["id"]).is_empty():
			scr.go_to(p["id"])
			break
	var who: String = scr.town.people_here()[0] if not scr.town.people_here().is_empty() else ""
	if who != "":
		scr.talk_to(who)
		scr.ask(who, "whereabouts")
		scr.ask(who, "window")
		scr.back_to_place()
	await _frames(1)
	# then everything else a careful player would do, through the same game
	var solver = CaseSolver.new(main.engine.package, main.engine)
	solver.gather()
	t.eq(Verdict.unseal_count, sealed_before, "the seal was opened during the investigation")
	t.check(main.engine.state["entries"].size() > 50, "the notebook is nearly empty")
	main.show_main_menu()
	await _frames(1)
	t.check(main.saves.has_save(FIRST), "the investigation was not saved")
	t.check(_find("ContinueButton") != null and not _find("ContinueButton").disabled, "Continue not offered")
	t.end()


func _restart_and_reveal(before: Dictionary) -> void:
	t.begin("after a restart: the generated cases are still there, the investigation resumes, and the truth is revealed")
	var entries_before: int = main.saves.load_state(FIRST)["entries"].size()
	main.queue_free()
	await _frames(1)
	main = load("res://scenes/main.tscn").instantiate()
	main.user_root = ROOT
	tree.root.add_child(main)
	_resize(Vector2(960, 640))
	await _frames(2)
	t.eq(main.current, "menu", "the game did not start at the menu")
	for id in [FIRST, SECOND]:
		var e: Dictionary = main.library.find(id)
		t.eq(e.get("source"), "generated", "%s is not in the library after a restart" % id)
	var generated := 0
	for f in _user_cases():
		generated += 1 if String(f).begins_with("godot-") and String(f).ends_with(".mcase") else 0
	t.check(generated >= 2, "generated case files after a restart: %d" % generated)
	t.eq(main.library.entries.size(), before["count"] + generated, "the library after a restart")
	t.eq(main.library.problems, [], "case files that do not load")
	# what was there before is as it was
	t.eq(main.library.find(before["imported"]).get("source"), "imported", "the imported case")
	t.eq(FileAccess.get_file_as_string(main.saves.save_path(before["bundled"])), before["save"],
			"the bundled case's saved investigation changed")
	await _press("ContinueButton")
	t.eq(main.current, "investigation", "Continue did not reopen the generated case")
	if main.current != "investigation":
		t.end()
		return
	t.eq(main.engine.case_id, FIRST, "Continue opened another case")
	t.check(main.engine.resumed, "the investigation was not resumed")
	t.eq(main.engine.state["entries"].size(), entries_before, "notebook entries lost after the restart")
	# the theory, through the tablet's form
	var solver = CaseSolver.new(main.engine.package, main.engine)
	solver.read_notebook()
	var d: Dictionary = solver.decide()
	t.check(d["ok"], "the notebook does not support a conclusion: %s" % d.get("reason", ""))
	if not d["ok"]:
		t.end()
		return
	var scr = main.screen
	scr.open_tablet("theory")
	await _frames(2)
	var mech: OptionButton = _find("TheoryMechanism")
	var resp: OptionButton = _find("TheoryResponsible")
	var mot: OptionButton = _find("TheoryMotive")
	var mechs: Array = main.engine.mechanisms()
	for i in range(mechs.size()):
		if mechs[i]["id"] == d["mechanism"]:
			mech.select(i)
	var rids: Array = scr.tablet.theory_widgets["rids"]
	resp.select(rids.find(d["responsible"]))
	var motives: Array = main.engine.motives()
	for i in range(motives.size()):
		if motives[i]["id"] == d["motive"]:
			mot.select(i)
	for eid in d["cites"]:
		var cb = _find("TheoryCite_" + String(eid))
		if cb != null:
			cb.button_pressed = true
			cb.toggled.emit(true)
	var sealed_before: int = Verdict.unseal_count
	scr.tablet.submit_from_form()
	await _frames(2)
	t.eq(main.current, "reveal", "the truth was not revealed")
	t.eq(Verdict.unseal_count, sealed_before + 1, "the seal was not opened exactly once, at the reveal")
	var score = _find("ScoreTotal")
	t.check(score != null and String(score.text).begins_with("Score:"), "no score")
	t.check(int(main.engine.state["score"]["total"]) >= 80, "the right answer scored %d" % int(main.engine.state["score"]["total"]))
	t.check(_find("Narrative") != null and String(_find("Narrative").text) != "", "no narrative")
	await _press("RevealMenuButton")
	t.check(main.continue_target().get("case_id") != FIRST, "a closed case offered to continue")
	# a generated case that was played is still offered as closed, and reopens to its truth
	main.open_case(main.library.find(FIRST), false)
	await _frames(1)
	t.eq(main.current, "reveal", "the closed generated case did not reopen to its truth")
	main.show_main_menu()
	await _frames(1)
	main.saves.reset_all()
	t.end()
