## End to end through the real interface: main menu -> new case -> talk, press, search, read,
## note, timeline, hint -> back to the menu -> Continue -> solve -> the truth.
extends RefCounted

const Verdict = preload("res://scripts/core/verdict.gd")

var t
var tree: SceneTree
var main


func run(t_, tree_: SceneTree) -> void:
	t = t_
	tree = tree_
	t.begin("a whole investigation through the interface")
	main = load("res://scenes/main.tscn").instantiate()
	main.user_root = "user://test_e2e/"
	tree.root.add_child(main)
	await _frames(2)
	main.saves.reset_all()
	main.show_main_menu()
	await _frames(1)
	t.check(main.current == "menu", "main menu not shown")
	t.check(_find("ContinueButton") != null and _find("ContinueButton").disabled, "Continue enabled without a save")

	await _press("NewCaseButton")
	t.check(main.current == "new_case", "New Case screen not shown")
	var entry: Dictionary = main.library.entries[0]
	await _press("StartCase_" + entry["case_id"])
	t.check(main.current == "investigation", "case did not open")
	var scr = main.screen
	var engine = main.engine
	var sealed_before: int = Verdict.unseal_count

	# people: talk, press, follow up
	await _press("Nav_people")
	var rid := ""
	for r in engine.data["residents"]:
		if r["condition"] != "deceased" and rid == "":
			rid = r["id"]
	await _press("Resident_" + rid)
	await _press("Topic_whereabouts")
	await _press("Topic_window")
	t.check(engine.state["ui"]["dialogue"].get(rid, []).size() == 2, "conversation history not recorded")
	t.check(engine.state["entries"].size() > 0, "nothing filed in the notebook")
	if _find("PressButton") != null:
		await _press("PressButton")
	await _press("AskAboutButton")

	# places and vehicles
	await _press("Nav_places")
	await _press("Place_square")
	await _press("SearchButton")
	t.check(engine.state["ui"]["searched"].has("square"), "square not searched")
	if not engine.data["vehicles"].is_empty():
		var vid: String = engine.data["vehicles"][0]["id"]
		await _press("Place_" + vid)
		await _press("SearchButton")
		t.check(engine.state["ui"]["searched"].has(vid), "vehicle not examined")

	# records
	await _press("Nav_records")
	var books: Array = engine.data["records"].keys()
	books.sort()
	await _press("Book_" + books[0])
	await _press("ReadButton")
	t.check(engine.state["ui"]["read"].has(books[0]), "record book not requested")

	# notebook and timeline
	await _press("Nav_notebook")
	scr.add_note("The timing of all this bothers me.", engine.data["hook"]["window"][0])
	await _frames(1)
	t.check(engine.entry("N1").get("text", "") == "The timing of all this bothers me.", "note not saved")
	await _press("Nav_timeline")
	t.check(_find("TimelineChart") != null, "timeline chart missing")
	await _press("Nav_case")

	# a hint (the confirmation dialog is bypassed by calling the action it confirms)
	var credits := int(engine.state["credits"])
	scr.buy_hint()
	await _frames(1)
	t.check(int(engine.state["credits"]) < credits, "hint did not cost credits")
	t.eq(Verdict.unseal_count, sealed_before, "the truth was opened during play")

	# leave and resume
	await _press("MenuButton")
	t.check(main.current == "menu", "Menu button did not return to the main menu")
	var cont = _find("ContinueButton")
	t.check(cont != null and not cont.disabled, "Continue not offered")
	var entries_before: int = engine.state["entries"].size()
	await _press("ContinueButton")
	t.check(main.current == "investigation", "Continue did not reopen the case")
	t.eq(main.engine.state["entries"].size(), entries_before, "progress lost on resume")
	t.eq(main.engine.state["ui"]["dialogue"].get(rid, []).size() >= 2, true, "conversation lost on resume")

	# solve
	scr = main.screen
	await _press("TheoryButton")
	t.check(_find("SubmitTheoryButton") != null, "theory form missing")
	var cite = _find("TheoryCite_S1")
	if cite != null:
		cite.button_pressed = true
		cite.toggled.emit(true)
	scr.submit_from_form()
	await _frames(2)
	t.check(main.current == "reveal", "the truth was not revealed after submitting")
	t.check(Verdict.unseal_count == sealed_before + 1, "the seal was not opened exactly once at the reveal")
	var score = _find("ScoreTotal")
	t.check(score != null and String(score.text).begins_with("Score:"), "score missing on the reveal")
	var narrative = _find("Narrative")
	t.check(narrative != null and String(narrative.text) != "", "narrative missing on the reveal")
	t.check(main.engine.state["revealed"], "case not closed")

	# a closed case reopens straight to its reveal
	await _press("RevealMenuButton")
	t.check(_find("ContinueButton").disabled, "Continue offered for a closed case")
	main.open_case(entry, false)
	await _frames(1)
	t.check(main.current == "reveal", "closed case did not reopen to the truth")

	# settings
	main.show_settings()
	await _frames(1)
	main.change_setting("text_size", 3)
	main.change_setting("high_contrast", true)
	t.eq(main.theme.default_font_size, 25, "text size not applied")
	main.change_setting("text_size", 1)
	main.change_setting("high_contrast", false)
	main.queue_free()
	await _frames(1)
	t.end()


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
