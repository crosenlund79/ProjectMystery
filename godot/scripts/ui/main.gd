## Project Mystery - the app: menus, case selection, saves, settings and screen routing.
##
## Layers (see docs/godot-migration.md):
##   scripts/core   case format, investigation rules, verdict, saves, library  (no UI)
##   scripts/ui     presentation only: everything the player clicks
##   scripts/sim    reserved for the future in-engine town simulation
extends Control

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const Kit = preload("res://scripts/ui/kit.gd")
const CaseLibrary = preload("res://scripts/core/case_library.gd")
const SaveStore = preload("res://scripts/core/save_store.gd")
const Investigation = preload("res://scripts/core/investigation.gd")
const Smoke = preload("res://scripts/core/smoke.gd")
const InvestigationScreen = preload("res://scripts/ui/investigation_screen.gd")
const RevealScreen = preload("res://scripts/ui/reveal_screen.gd")

const DIFFICULTY_HELP := {
	"gentle": "Several people saw or heard something useful.",
	"standard": "A fair puzzle: the evidence is there if you look.",
	"hard": "Thin evidence. 'Cannot be determined' may be the honest answer.",
	"very hard": "Very little survived. Expect uncertainty.",
}

var user_root := "user://"
var library
var saves
var settings: Dictionary = {}
var engine = null
var screen: Control = null
var current := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--smoke-test"):
			var out := a.get_slice("=", 1) if a.contains("=") else ""
			get_tree().quit(Smoke.run(out))
			return
	setup(user_root)


func setup(root: String) -> void:
	user_root = root
	library = CaseLibrary.new(root)
	saves = SaveStore.new(root)
	settings = saves.load_settings()
	apply_settings()
	show_main_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		persist()


func apply_settings() -> void:
	theme = ThemeBuilder.build(settings)
	if DisplayServer.get_name() != "headless":
		var full: bool = settings.get("fullscreen", false)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_min_size(Vector2i(960, 640))


func persist() -> void:
	if engine != null:
		saves.save(engine.state)


func _set_screen(node: Control, name_: String) -> void:
	if screen != null:
		remove_child(screen)
		screen.queue_free()
	current = name_
	screen = node
	node.name = "Screen_" + name_
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(node)


func _backdrop(content: Control) -> PanelContainer:
	var bg := Kit.panel("Backdrop")
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bg.add_child(content)
	return bg


func _header(title: String, back_label := "Back to main menu") -> HBoxContainer:
	var h := Kit.hbox()
	var back := Kit.button("◂ " + back_label, "Return to the main menu (Esc)", "", "BackButton")
	back.pressed.connect(show_main_menu)
	h.add_child(back)
	var t := Kit.label(title, "TitleLabel")
	h.add_child(t)
	return h


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and current in ["new_case", "load", "settings"]:
		show_main_menu()
		get_viewport().set_input_as_handled()


# =========================================================================== main menu
func continue_target() -> Dictionary:
	## The most recently played unfinished investigation that still exists in the library.
	for s in saves.list_saves():
		if s["revealed"]:
			continue
		var e: Dictionary = library.find(s["case_id"])
		if not e.is_empty():
			return e
	return {}


func show_main_menu() -> void:
	persist()
	engine = null
	var col := Kit.vbox(14)
	col.custom_minimum_size = Vector2(440, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(Kit.spacer(40))
	col.add_child(Kit.label("PROJECT MYSTERY", "TitleLabel"))
	col.add_child(Kit.label("A small town. Something happened. Find out what — if you can.", "MutedLabel"))
	col.add_child(Kit.spacer(18))
	var target := continue_target()
	var items := [
		["New Case", "Choose a case from the library and begin a fresh investigation.", "NewCaseButton", show_new_case],
		["Continue", "Pick up where you left off: %s" % target.get("title", "") if not target.is_empty()
				else "No investigation in progress yet.", "ContinueButton", func(): open_case(continue_target(), false)],
		["Load Case", "Your saved investigations, or import a case file.", "LoadCaseButton", show_load],
		["Settings", "Text size, contrast and display.", "SettingsButton", show_settings],
		["Quit", "Close the game. Your progress is saved.", "QuitButton", quit_game],
	]
	var first: Button = null
	for it in items:
		var b := Kit.button(it[0], it[1], "PrimaryButton" if it[2] == "NewCaseButton" else "", it[2])
		b.custom_minimum_size = Vector2(0, 52)
		b.pressed.connect(it[3])
		if it[2] == "ContinueButton" and target.is_empty():
			b.disabled = true
		col.add_child(b)
		if first == null and not b.disabled:
			first = b
	col.add_child(Kit.spacer(24))
	col.add_child(Kit.label("Every clue, lie and mistake comes from a simulated town. Nothing is scripted.",
			"SmallLabel"))
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(col)
	_set_screen(_backdrop(center), "menu")
	if first != null and is_inside_tree():
		first.call_deferred("grab_focus")


func quit_game() -> void:
	persist()
	get_tree().quit()


# =========================================================================== new case
func _status_for(case_id: String) -> String:
	var st = saves.load_state(case_id)
	if st == null:
		return "Not started"
	if st.get("revealed", false):
		var sc = st.get("score")
		return "Closed — scored %d/100" % int(sc.get("total", 0)) if typeof(sc) == TYPE_DICTIONARY else "Closed"
	if st.get("concluded", false):
		return "Theory submitted — the truth is waiting"
	return "In progress — %d notebook entries" % st.get("entries", []).size()


func show_new_case(filter := "all") -> void:
	var root := Kit.vbox(12)
	root.add_child(_header("New Case"))
	root.add_child(Kit.label("Each case comes from a real simulated history. Pick one by its season and how much "
			+ "the town gives away. The details are for you to find.", "MutedLabel"))
	var filters := [["All difficulties", 0], ["Gentle", 1], ["Standard", 2], ["Hard", 3]]
	var keys := ["all", "gentle", "standard", "hard"]
	var opt := Kit.option(filters, keys.find(filter), "Show only cases of one difficulty")
	opt.name = "DifficultyFilter"
	opt.item_selected.connect(func(i): show_new_case(keys[i]))
	var row := Kit.hbox()
	row.add_child(Kit.label("Show:", "", false))
	row.add_child(opt)
	root.add_child(row)
	var list := Kit.vbox(12)
	for e in library.entries:
		if filter != "all" and e["difficulty"] != filter:
			continue
		list.add_child(_case_card(e))
	if list.get_child_count() == 0:
		list.add_child(Kit.label("No cases match.", "MutedLabel"))
	root.add_child(Kit.scroll(list))
	_set_screen(_backdrop(Kit.margin(root)), "new_case")


func _case_card(e: Dictionary) -> Control:
	var card := Kit.panel("Card")
	var v := Kit.vbox(6)
	v.add_child(Kit.label(e["title"], "HeadingLabel"))
	v.add_child(Kit.label("%s  ·  %s  ·  starts %s" % [e["town"], e["season"], e["start_label"]], "MutedLabel"))
	var diff: String = e["difficulty"]
	v.add_child(Kit.label("Difficulty: %s — %s" % [diff.capitalize(), DIFFICULTY_HELP.get(diff, "")], "SmallLabel"))
	var status := _status_for(e["case_id"])
	v.add_child(Kit.label(status, "AccentLabel" if status != "Not started" else "SmallLabel"))
	var buttons := Kit.hbox()
	var started: bool = saves.has_save(e["case_id"])
	var go := Kit.button("Continue" if started else "Begin investigating",
			"Open this case" if started else "Start this case from the beginning", "PrimaryButton",
			"StartCase_" + e["case_id"])
	go.pressed.connect(func(): open_case(e, false))
	buttons.add_child(go)
	if started:
		var again := Kit.button("Start over", "Discard your notes for this case and begin again", "DangerButton",
				"Restart_" + e["case_id"])
		again.pressed.connect(confirm.bind("Start over?",
				"This erases your notebook and conversations for \"%s\"." % e["title"], open_case.bind(e, true), "Start over"))
		buttons.add_child(again)
	v.add_child(buttons)
	card.add_child(v)
	return card


# =========================================================================== load case
func show_load() -> void:
	var root := Kit.vbox(12)
	root.add_child(_header("Load Case"))
	var import_row := Kit.hbox()
	var imp := Kit.button("Import a case file…", "Add a .mcase file made by the Project Mystery laboratory", "",
			"ImportButton")
	imp.pressed.connect(_choose_import)
	import_row.add_child(imp)
	import_row.add_child(Kit.label("Case files (.mcase) come from the simulation laboratory.", "SmallLabel"))
	root.add_child(import_row)
	var list := Kit.vbox(10)
	var any := false
	for s in saves.list_saves():
		var e: Dictionary = library.find(s["case_id"])
		if e.is_empty():
			continue
		any = true
		var card := Kit.panel("Card")
		var v := Kit.vbox(6)
		v.add_child(Kit.label(e["title"], "HeadingLabel"))
		var bias: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		var when := Time.get_datetime_string_from_unix_time(int(s["saved_at"]) + bias, true).substr(0, 16)
		v.add_child(Kit.label("%s  ·  %s  ·  last played %s" % [e["town"], _status_for(e["case_id"]), when], "MutedLabel"))
		var h := Kit.hbox()
		var open := Kit.button("Review the truth" if s["revealed"] else "Continue", "Open this investigation", "PrimaryButton",
				"Open_" + e["case_id"])
		open.pressed.connect(func(): open_case(e, false))
		h.add_child(open)
		var del := Kit.button("Delete", "Delete this saved investigation", "DangerButton", "Delete_" + e["case_id"])
		del.pressed.connect(confirm.bind("Delete this investigation?",
				"Your notes for \"%s\" will be lost." % e["title"], _delete_save.bind(e["case_id"]), "Delete"))
		h.add_child(del)
		v.add_child(h)
		card.add_child(v)
		list.add_child(card)
	if not any:
		list.add_child(Kit.label("No saved investigations yet. Choose New Case to begin.", "MutedLabel"))
	for p in library.problems:
		list.add_child(Kit.label("Could not load a case file: " + p, "DangerLabel"))
	root.add_child(Kit.scroll(list))
	_set_screen(_backdrop(Kit.margin(root)), "load")


func _choose_import() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.mcase ; Project Mystery case"])
	fd.title = "Import a case file"
	fd.use_native_dialog = true
	fd.file_selected.connect(func(path): import_case(path))
	add_child(fd)
	fd.popup_centered_ratio(0.7)


func import_case(path: String) -> Dictionary:
	var r: Dictionary = library.import_file(path)
	if r["ok"]:
		message("Case imported", "The case is now in your library under New Case.")
	else:
		message("Could not import this file", "\n".join(PackedStringArray(r["errors"].slice(0, 6))))
	if current == "load":
		show_load()
	return r


# =========================================================================== settings
func show_settings() -> void:
	var root := Kit.vbox(16)
	root.add_child(_header("Settings"))
	var card := Kit.panel("Card")
	var v := Kit.vbox(14)
	var sizes := []
	for i in range(ThemeBuilder.SIZE_NAMES.size()):
		sizes.append([ThemeBuilder.SIZE_NAMES[i], i])
	var size_row := Kit.hbox()
	size_row.add_child(Kit.label("Text size", "", false))
	var size_opt := Kit.option(sizes, int(settings["text_size"]), "Make all text larger or smaller")
	size_opt.name = "TextSize"
	size_opt.item_selected.connect(func(i): change_setting("text_size", i))
	size_row.add_child(size_opt)
	v.add_child(size_row)
	var hc := CheckButton.new()
	hc.name = "HighContrast"
	hc.text = "High contrast"
	hc.tooltip_text = "Black background, white text and bright highlights"
	hc.button_pressed = settings["high_contrast"]
	hc.toggled.connect(func(on): change_setting("high_contrast", on))
	v.add_child(hc)
	var fs := CheckButton.new()
	fs.name = "Fullscreen"
	fs.text = "Fullscreen"
	fs.button_pressed = settings["fullscreen"]
	fs.toggled.connect(func(on): change_setting("fullscreen", on))
	v.add_child(fs)
	v.add_child(HSeparator.new())
	var reset := Kit.button("Reset all progress", "Delete every saved investigation", "DangerButton", "ResetButton")
	reset.pressed.connect(confirm.bind("Reset all progress?", "Every saved investigation will be deleted.", _reset_all,
			"Delete everything"))
	v.add_child(reset)
	v.add_child(Kit.label("Saves are kept in: " + ProjectSettings.globalize_path(user_root), "SmallLabel"))
	card.add_child(v)
	root.add_child(card)
	_set_screen(_backdrop(Kit.margin(root)), "settings")


func change_setting(key: String, value) -> void:
	settings[key] = value
	saves.save_settings(settings)
	apply_settings()


# =========================================================================== cases
func open_case(entry: Dictionary, fresh: bool) -> bool:
	if entry.is_empty():
		return false
	var loaded: Dictionary = library.load_package(entry)
	if not loaded["ok"]:
		message("This case cannot be opened", "\n".join(PackedStringArray(loaded["errors"].slice(0, 6))))
		return false
	if fresh:
		saves.delete_save(entry["case_id"])
	var state = null if fresh else saves.load_state(entry["case_id"])
	engine = Investigation.new(loaded["package"], state)
	persist()
	if engine.save_mismatch:
		message("This case has changed", "This case was updated since you last played it, so your earlier notes no longer fit it. The investigation starts afresh.")
	if engine.state["revealed"]:
		var res: Dictionary = engine.reveal()
		show_reveal(res["model"])
	else:
		_set_screen(InvestigationScreen.new(self, engine), "investigation")
	return true


func show_reveal(model: Dictionary) -> void:
	persist()
	_set_screen(RevealScreen.new(self, engine, model), "reveal")


# =========================================================================== dialogs
func message(title: String, text: String) -> AcceptDialog:
	var d := AcceptDialog.new()
	d.title = title
	d.dialog_text = text
	d.dialog_autowrap = true
	d.min_size = Vector2i(460, 0)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
	return d


func confirm(title: String, text: String, on_yes: Callable, yes_label := "Yes") -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.title = title
	d.dialog_text = text
	d.dialog_autowrap = true
	d.min_size = Vector2i(460, 0)
	d.ok_button_text = yes_label
	d.cancel_button_text = "Cancel"
	d.confirmed.connect(_confirmed.bind(d, on_yes))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
	return d


func _confirmed(d: ConfirmationDialog, on_yes: Callable) -> void:
	d.queue_free()
	on_yes.call()


func _delete_save(case_id: String) -> void:
	saves.delete_save(case_id)
	show_load()


func _reset_all() -> void:
	saves.reset_all()
	message("Done", "All saved investigations were deleted.")
