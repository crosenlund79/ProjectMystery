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
	# A headless script run has a 64x64 window; lay the game out at the smallest window it allows instead.
	_resize(Vector2(960, 640))
	await _frames(2)
	main.saves.reset_all()
	main.show_main_menu()
	await _frames(1)
	t.check(main.current == "menu", "main menu not shown")
	t.check(_find("ContinueButton") != null and _find("ContinueButton").disabled, "Continue enabled without a save")
	await _layout("main menu")

	await _press("NewCaseButton")
	t.check(main.current == "new_case", "New Case screen not shown")
	await _layout("new case")
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
	await _layout("people")

	# places and vehicles
	await _press("Nav_places")
	await _press("Place_square")
	await _press("SearchButton")
	t.check(engine.state["ui"]["searched"].has("square"), "square not searched")
	await _layout("places")
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
	await _layout("records")

	# notebook and timeline
	await _press("Nav_notebook")
	scr.add_note("The timing of all this bothers me.", engine.data["hook"]["window"][0])
	await _frames(1)
	t.check(engine.entry("N1").get("text", "") == "The timing of all this bothers me.", "note not saved")
	await _layout("notebook")
	await _press("Nav_timeline")
	t.check(_find("TimelineChart") != null, "timeline chart missing")
	await _layout("timeline")
	await _press("Nav_case")
	await _layout("case file")

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
	await _layout("theory")
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
	await _layout("reveal")

	# a closed case reopens straight to its reveal
	await _press("RevealMenuButton")
	t.check(_find("ContinueButton").disabled, "Continue offered for a closed case")
	main.open_case(entry, false)
	await _frames(1)
	t.check(main.current == "reveal", "closed case did not reopen to the truth")

	# settings
	main.show_settings()
	await _frames(1)
	await _layout("settings")
	main.change_setting("text_size", 3)
	main.change_setting("high_contrast", true)
	t.eq(main.theme.default_font_size, 25, "text size not applied")
	_resize(Vector2(1280, 800))
	await _layout("settings, extra large text")

	# every screen again at the largest text size, on a second case
	main.show_load()
	await _layout("load case, extra large text")
	var second: Dictionary = main.library.entries[1]
	main.open_case(second, true)
	await _frames(1)
	t.check(main.current == "investigation", "second case did not open")
	var eng2 = main.engine
	var who := ""
	for r in eng2.data["residents"]:
		if r["condition"] != "deceased" and who == "":
			who = r["id"]
	main.screen.select_resident(who)
	main.screen.ask(who, "whereabouts")
	main.screen.ask(who, "incident")
	await _layout("people, extra large text")
	main.screen.search_place(eng2.data["places"][0]["id"])
	await _layout("places, extra large text")
	var books2: Array = eng2.data["records"].keys()
	books2.sort()
	main.screen.read_book(books2[0])
	await _layout("records, extra large text")
	for pg in ["case", "notebook", "timeline", "theory"]:
		main.screen.show_page(pg)
		await _layout(pg + ", extra large text")
	main.show_main_menu()
	await _layout("main menu, extra large text")
	main.change_setting("text_size", 1)
	main.change_setting("high_contrast", false)
	main.saves.reset_all()
	main.queue_free()
	await _frames(1)
	t.end()


func _resize(to: Vector2) -> void:
	main.anchor_right = 0.0
	main.anchor_bottom = 0.0
	main.position = Vector2.ZERO
	main.size = to


func _layout(where: String) -> void:
	## Headless Godot still lays out Controls, so the sizes are real: nothing squeezed, collapsed or off screen.
	await _frames(2)
	var view: Vector2 = main.size
	var problems := []
	_walk(main.screen, view, problems)
	t.check(problems.is_empty(), "layout on %s (window %dx%d): %s" % [where, int(view.x), int(view.y),
			"; ".join(PackedStringArray(problems.slice(0, 5)))])


func _walk(node: Node, view: Vector2, problems: Array) -> void:
	if node is Window:
		return
	if node is Control:
		var c: Control = node as Control
		if not c.is_visible_in_tree():
			return
		var r := c.get_global_rect()
		var what := "%s '%s'" % [c.get_class(), String(c.name)]
		if c is Label:
			var lab: Label = c as Label
			if lab.autowrap_mode != TextServer.AUTOWRAP_OFF and lab.text.length() > 12 and r.size.x < 80:
				problems.append("%s squeezed to %d px: %s" % [what, int(r.size.x), lab.text.left(30)])
		if c is BaseButton and (r.size.x < 16 or r.size.y < 16):
			problems.append("%s collapsed to %dx%d" % [what, int(r.size.x), int(r.size.y)])
		if view.x > 100 and r.end.x > view.x + 2:
			problems.append("%s runs off the right edge (to %d px)" % [what, int(r.end.x)])
		if String(c.name) == "TimelineChart" and r.size.y < 60:
			problems.append("timeline chart collapsed")
	for ch in node.get_children():
		_walk(ch, view, problems)


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
