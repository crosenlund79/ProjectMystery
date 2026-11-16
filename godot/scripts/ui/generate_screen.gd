## New Case > Generate Mystery: simulate a new town and keep a mystery from it that can be solved from the evidence.
##
## Four views on one screen:
##   form     town size, conditions, how many days, an optional seed, and how many towns to try at most;
##   running  the attempt, the seed, the day of the town being simulated, and what is being done - nothing that would
##            give the case away (no names of culprits, no motives, no incidents, no sealed evidence); Cancel;
##   found    the new case's card (as the case library shows it), with Investigate, Generate Another and Case Library;
##   failed   no town gave a fair mystery: Retry or Back.
## The work is done by scripts/cases/case_generation_job.gd, a little each frame (no threads), and nothing else runs
## meanwhile: no investigation is open and no other town is simulated.
extends Control

const Kit = preload("res://scripts/ui/kit.gd")
const Job = preload("res://scripts/cases/case_generation_job.gd")
const SimConfig = preload("res://scripts/sim/sim_config.gd")

## Work per frame, in milliseconds: small enough to keep the screen moving, large enough not to waste frames.
const FRAME_BUDGET_MS := 12
const SIZE_ITEMS := [["8 residents", 8], ["10 residents", 10], ["12 residents", 12]]
const PROFILE_ITEMS := [["Normal", 0], ["Scarcity", 1], ["Crisis", 2], ["Tension", 3]]

var app
var settings: Dictionary  # residents, profile, days, seed (int or null), attempts
var job = null
var view := ""
var note := ""  # one line shown above the form (after a cancel, or an invalid entry)
var body: VBoxContainer
var _bar: ProgressBar
var _attempt_label: Label
var _day_label: Label
var _phase_label: Label
var _checked_label: Label


static func default_settings() -> Dictionary:
	return {"residents": 10, "profile": "normal", "days": Job.DEFAULT_DAYS, "seed": null,
			"attempts": Job.DEFAULT_ATTEMPTS}


func _init(app_, settings_: Dictionary) -> void:
	app = app_
	settings = default_settings()
	settings.merge(settings_, true)


func _ready() -> void:
	var bg := Kit.panel("Backdrop")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	body = Kit.vbox(12)
	bg.add_child(Kit.margin(Kit.scroll(body)))
	show_form()


func _process(_delta: float) -> void:
	if job == null or view != "running":
		return
	job.step(FRAME_BUDGET_MS)
	_update_progress()
	if not job.running():
		_finished()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if view == "running":
		cancel()
	elif view == "form":
		app.show_new_case()
	get_viewport().set_input_as_handled()


# ================================================================ the form
func show_form() -> void:
	view = "form"
	job = null
	Kit.clear(body)
	body.add_child(_top("◂ Back to New Case", "GenerateBackButton", Callable(app, "show_new_case")))
	body.add_child(Kit.label("Generate Mystery", "TitleLabel"))
	body.add_child(Kit.label("A new town is simulated from its first day. Only a mystery that can be solved from what "
			+ "you will be able to find out is kept. Simulating a town takes a little while; if it gives no fair mystery, "
			+ "another town is tried.", "MutedLabel"))
	if note != "":
		var n := Kit.label(note, "AccentLabel")
		n.name = "GenerateNote"
		body.add_child(n)
	var card := Kit.panel("Card")
	var v := Kit.vbox(12)
	var size_opt := Kit.option(SIZE_ITEMS, maxi(0, Job.SIZES.find(int(settings["residents"]))), "How many people live in the town")
	size_opt.name = "TownSize"
	v.add_child(_row("Town size", size_opt))
	var prof_opt := Kit.option(PROFILE_ITEMS, maxi(0, Job.PROFILES.find(String(settings["profile"]))),
			"The season the town lives through")
	prof_opt.name = "Conditions"
	v.add_child(_row("Conditions", prof_opt))
	var prof_help := Kit.label(_profile_help(String(settings["profile"])), "SmallLabel")
	prof_help.name = "ConditionsHelp"
	v.add_child(prof_help)
	prof_opt.item_selected.connect(func(i): prof_help.text = _profile_help(Job.PROFILES[i]))
	var days := _spin("Days", Job.MIN_DAYS, Job.MAX_DAYS, int(settings["days"]),
			"How many days of the town's life to simulate, at most")
	days.suffix = "days"
	v.add_child(_row("Simulation", days))
	var seed_edit := LineEdit.new()
	seed_edit.name = "Seed"
	seed_edit.placeholder_text = "Random"
	seed_edit.text = "" if settings["seed"] == null else str(int(settings["seed"]))
	seed_edit.tooltip_text = "Leave empty for a random town. The same seed and settings always give the same town."
	seed_edit.custom_minimum_size = Vector2(180, 0)
	v.add_child(_row("Seed (optional)", seed_edit))
	var attempts := _spin("Attempts", 1, Job.MAX_ATTEMPTS, int(settings["attempts"]),
			"If a town gives no fair mystery, the next seed is tried, up to this many towns")
	attempts.suffix = "towns"
	v.add_child(_row("Try at most", attempts))
	card.add_child(v)
	body.add_child(card)
	var buttons := Kit.hbox()
	var go := Kit.button("Generate", "Simulate a town and find a mystery in it", "PrimaryButton", "GenerateButton")
	go.pressed.connect(func(): start_from_form())
	buttons.add_child(go)
	body.add_child(buttons)
	if is_inside_tree():
		go.call_deferred("grab_focus")


func _profile_help(p: String) -> String:
	return String(SimConfig.PROFILES.get(p, {}).get("description", ""))


func _row(label: String, field: Control) -> HBoxContainer:
	var h := Kit.hbox(12)
	var l := Kit.label(label, "", false)
	l.custom_minimum_size = Vector2(170, 0)
	h.add_child(l)
	h.add_child(field)
	return h


func _spin(name_: String, lo: int, hi: int, value: int, tip: String) -> SpinBox:
	var s := SpinBox.new()
	s.name = name_
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = value
	s.tooltip_text = tip
	s.custom_minimum_size = Vector2(150, 0)
	return s


func _top(back_label: String, back_name: String, on_back: Callable) -> HBoxContainer:
	var h := Kit.hbox()
	var back := Kit.button(back_label, "Go back", "", back_name)
	back.pressed.connect(on_back)
	h.add_child(back)
	return h


func read_form() -> Dictionary:
	## The settings as entered, or {"error": ...}.
	var out := {}
	out["residents"] = Job.SIZES[clampi((find_child("TownSize", true, false) as OptionButton).selected, 0, 2)]
	out["profile"] = Job.PROFILES[clampi((find_child("Conditions", true, false) as OptionButton).selected, 0, 3)]
	out["days"] = int((find_child("Days", true, false) as SpinBox).value)
	out["attempts"] = int((find_child("Attempts", true, false) as SpinBox).value)
	var text := (find_child("Seed", true, false) as LineEdit).text.strip_edges()
	out["seed"] = null
	if text != "":
		if not text.is_valid_int() or int(text) < 1 or int(text) > Job.MAX_SEED:
			return {"error": "The seed must be a whole number from 1 to %d, or left empty for a random town." % Job.MAX_SEED}
		out["seed"] = int(text)
	return out


func start_from_form() -> void:
	var s := read_form()
	if s.has("error"):
		note = s["error"]
		show_form()
		return
	settings = s
	app.generate_settings = settings.duplicate()
	start(settings, [])


# ================================================================ generating
func start(request: Dictionary, exclude: Array) -> void:
	## Begin a request: request is settings with the seed to start from (null for a random one).
	note = ""
	var r := request.duplicate()
	r["library_dir"] = app.library.user_cases
	r["exclude"] = exclude
	job = Job.new(r)
	if not job.running():
		note = job.error_message
		show_form()
		return
	view = "running"
	Kit.clear(body)
	body.add_child(Kit.label("Generating a mystery", "TitleLabel"))
	body.add_child(Kit.label("Simulating a town from its first day, then testing whether what happened there can be "
			+ "worked out from the evidence. Nothing about the case is shown until you investigate it.", "MutedLabel"))
	var card := Kit.panel("Card")
	var v := Kit.vbox(10)
	_attempt_label = Kit.label("", "HeadingLabel")
	_attempt_label.name = "AttemptLabel"
	v.add_child(_attempt_label)
	_bar = ProgressBar.new()
	_bar.name = "GenerateProgress"
	_bar.min_value = 0
	_bar.max_value = job.days
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 26)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_bar)
	_day_label = Kit.label("", "MutedLabel")
	_day_label.name = "DayLabel"
	v.add_child(_day_label)
	_phase_label = Kit.label("", "")
	_phase_label.name = "PhaseLabel"
	v.add_child(_phase_label)
	_checked_label = Kit.label("", "SmallLabel")
	_checked_label.name = "CheckedLabel"
	v.add_child(_checked_label)
	card.add_child(v)
	body.add_child(card)
	var cancel_b := Kit.button("Cancel", "Stop generating (Esc). Nothing is saved.", "DangerButton", "CancelGenerateButton")
	cancel_b.pressed.connect(func(): cancel())
	body.add_child(cancel_b)
	_update_progress()


func _update_progress() -> void:
	if job == null or _bar == null or not is_instance_valid(_bar):
		return
	_attempt_label.text = "Town %d of %d  ·  seed %d  ·  %d residents  ·  %s  ·  %d days" % [maxi(1, job.attempt),
			job.max_attempts, job.town_seed if job.attempt > 0 else job.first_seed, job.residents,
			String(job.profile).capitalize(), job.days]
	_bar.value = job.day
	_day_label.text = "Day %d of %d" % [job.day, job.days]
	_phase_label.text = {"simulating": "Simulating the town", "checking": job.detail,
			"saving": job.detail}.get(job.phase, "Starting")
	_checked_label.text = "Possible cases looked at so far: %d" % job.checked


func cancel() -> void:
	if job != null:
		job.cancel()
	note = "Generation cancelled. Nothing was saved."
	show_form()


func _finished() -> void:
	match String(job.status):
		"found":
			app.library.refresh()
			show_found()
		"failed":
			show_failed()
		"cancelled":
			show_form()
		_:
			note = job.error_message
			show_form()


# ================================================================ the result
func show_found() -> void:
	view = "found"
	var r: Dictionary = job.result
	Kit.clear(body)
	var title := "This mystery is already in your case library" if r["existed"] else "A mystery is ready"
	var head := Kit.label(title, "TitleLabel")
	head.name = "FoundTitle"
	body.add_child(head)
	var card := Kit.panel("Card")
	card.name = "FoundCard"
	var v := Kit.vbox(6)
	v.add_child(Kit.label(r["title"], "HeadingLabel"))
	v.add_child(Kit.label("%s  ·  %s  ·  starts %s" % [r["town"], r["season"], r["start_label"]], "MutedLabel"))
	var diff: String = r["difficulty"]
	v.add_child(Kit.label("Difficulty: %s — %s" % [diff.capitalize(), app.difficulty_help(diff)], "SmallLabel"))
	v.add_child(Kit.label("Seed %d  ·  %d residents  ·  %d days  ·  found in town %d of %d" % [r["seed"], r["residents"],
			r["days"], r["attempt"], job.max_attempts], "SmallLabel"))
	card.add_child(v)
	body.add_child(card)
	body.add_child(Kit.label("It is saved in your case library, beside the other cases. The same seed and settings "
			+ "always give the same mystery.", "SmallLabel"))
	var buttons := Kit.flow()
	var go := Kit.button("Investigate", "Open this case", "PrimaryButton", "InvestigateButton")
	go.pressed.connect(func(): investigate())
	buttons.add_child(go)
	var again := Kit.button("Generate Another", "Find another mystery with the same settings", "", "GenerateAnotherButton")
	again.pressed.connect(func(): generate_another())
	buttons.add_child(again)
	var lib := Kit.button("Case Library", "All your cases", "", "CaseLibraryButton")
	lib.pressed.connect(Callable(app, "show_new_case"))
	buttons.add_child(lib)
	body.add_child(buttons)
	if is_inside_tree():
		go.call_deferred("grab_focus")


func investigate() -> void:
	var entry: Dictionary = app.library.find(job.result["case_id"])
	if entry.is_empty():
		app.message("This case cannot be opened", "It is no longer in your case library.")
		return
	app.open_case(entry, false)


func generate_another() -> void:
	## The same settings. With a seed chosen, the same town is looked at again, then the next ones; otherwise a new
	## random town. Cases already in the library are not offered again.
	var r := settings.duplicate()
	if settings["seed"] != null:
		r["seed"] = job.result["seed"]
	start(r, _library_ids())


func _library_ids() -> Array:
	var ids := []
	for e in app.library.entries:
		ids.append(e["case_id"])
	return ids


func show_failed() -> void:
	view = "failed"
	Kit.clear(body)
	var head := Kit.label("No mystery found", "TitleLabel")
	head.name = "FailedTitle"
	body.add_child(head)
	body.add_child(Kit.label("%d %s simulated, but none gave a mystery that can be fairly solved from the evidence: "
			% [job.max_attempts, "town was" if job.max_attempts == 1 else "towns were"]
			+ "most of what happens in a town leaves too little behind. Nothing was saved. Try again with new towns, or "
			+ "go back and change the settings (troubled and lean seasons give more mysteries, and so does trying more "
			+ "towns).", "MutedLabel"))
	var buttons := Kit.hbox()
	var retry := Kit.button("Retry", "Try new towns with the same settings", "PrimaryButton", "RetryButton")
	retry.pressed.connect(func(): retry_failed())
	buttons.add_child(retry)
	var back := Kit.button("Back", "Back to the settings", "", "FailedBackButton")
	back.pressed.connect(func(): show_form())
	buttons.add_child(back)
	body.add_child(buttons)


func retry_failed() -> void:
	## The towns after the ones just tried (with a seed chosen), or new random ones.
	var r := settings.duplicate()
	if settings["seed"] != null:
		r["seed"] = job.seed_for(job.max_attempts + 1)
	start(r, _library_ids())
