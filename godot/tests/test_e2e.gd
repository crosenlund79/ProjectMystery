## End to end through the real interface: main menu -> new case -> arrive in town -> walk, meet
## people, talk, press, follow up -> look around -> read a record book where it is kept -> examine a
## vehicle -> open the tablet (notes, evidence, people, timeline, hints, locked case files) -> leave
## -> Continue -> solve -> the truth. Every screen's layout is checked at the smallest window the
## game allows, then again at the largest text size.
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
	# play this one as a Hobby Detective
	var mode_opt = _find("ModeOption")
	t.check(mode_opt != null, "no detective mode choice on the New Case screen")
	if mode_opt != null:
		mode_opt.select(1)
		mode_opt.item_selected.emit(1)
		await _frames(1)
	await _press("StartCase_" + entry["case_id"])
	t.check(main.current == "investigation", "case did not open")
	t.eq(main.engine.mode(), "hobby", "the case did not start in Hobby Detective mode")
	var scr = main.screen
	var engine = main.engine
	var town = scr.town
	var sealed_before: int = Verdict.unseal_count

	# --- arriving in town
	t.eq(town.at(), town.start_place(), "you arrive in the square")
	t.check(_find("TownMap") != null, "town map missing")
	t.check(_find("ArrivalCard") != null, "no arrival card with the case")
	t.check(not scr.tablet.visible, "the tablet should start closed")
	t.check(_find("Tile_" + _node(town.scene())) != null, "the scene is not on the map")
	t.check(_find("PlaceArt") != null, "the place you are at is not illustrated in the side panel")
	await _layout("town, arrival")
	# the map marks where you are, where it happened, and where you have not been yet
	t.eq(String(_find("Tile_" + _node(town.at())).theme_type_variation), "MapTileHere", "current place not marked")
	if town.scene() != town.at():
		t.eq(String(_find("Tile_" + _node(town.scene())).theme_type_variation), "MapTileScene", "the scene not marked")
	var unvisited := 0
	for p in town.places():
		if not town.visited(p["id"]) and p["id"] != town.scene():
			unvisited += 1
			t.eq(String(_find("Tile_" + _node(p["id"])).theme_type_variation), "MapTileUnvisited", "unvisited place not marked")
	t.check(unvisited > 0, "no unvisited places at the start")
	if _find("GoToScene") != null:
		await _press("GoToScene")
		t.eq(town.at(), town.scene(), "Go to the scene did not walk there")

	# --- walk to someone and talk
	var target := ""
	var target_place := ""
	for p in town.places():
		for rid in town.people_at(p["id"]):
			if target == "" and engine.data["testimony"].has(rid):
				target = rid
				target_place = p["id"]
	t.check(target != "", "nobody to talk to in this town")
	await _press("Tile_" + _node(target_place))
	t.eq(town.at(), target_place, "clicking a building did not walk there")
	t.check(_find("Talk_" + target) != null, "the person who is here is not offered to talk to")
	await _press("Talk_" + target)
	await _press("Topic_whereabouts")
	await _press("Topic_window")
	t.check(engine.state["ui"]["dialogue"].get(target, []).size() == 2, "conversation history not recorded")
	t.check(engine.state["entries"].size() > 0, "nothing filed in the notebook")
	if _find("PressButton") != null:
		await _press("PressButton")
	await _press("AskAboutButton")
	await _layout("conversation")
	await _press("BackToPlace")
	t.check(scr.view == "place", "Back did not return to the place")
	await _press("LookAroundButton")
	t.check(engine.state["ui"]["searched"].has(target_place), "looking around was not recorded")

	# --- a record book, where it is kept
	var books: Array = engine.data["records"].keys()
	books.sort()
	var book: String = books[0]
	var book_place: String = town.record_place(book)
	await _press("Tile_" + _node(book_place))
	t.check(_find("ReadBook_" + book) != null, "the record book is not offered where it is kept")
	for k in books:
		if town.record_place(k) != book_place:
			t.check(_find("ReadBook_" + k) == null, "a book kept elsewhere is offered here")
	await _press("ReadBook_" + book)
	await _press("ReadButton")
	t.check(engine.state["ui"]["read"].has(book), "record book not requested")
	if engine.state["ui"]["read"][book]["allowed"] and not engine.data["records"][book]["entries"].is_empty():
		var first_line: String = engine.data["records"][book]["entries"][0]["id"]
		await _press("Cite_" + first_line.replace("#", "_").replace("-", "_"))
		t.check(engine.state["by_ref"].has(first_line), "copying a record line did not reach the notebook")
	await _layout("record book")

	# --- a vehicle, where it is parked
	if not engine.data["vehicles"].is_empty():
		var veh: Dictionary = engine.data["vehicles"][0]
		await _press("Tile_" + _node(veh["location"]))
		await _press("Examine_" + veh["id"])
		await _press("SearchButton")
		t.check(engine.state["ui"]["searched"].has(veh["id"]), "vehicle not examined")
		await _layout("vehicle")

	# --- people you have seen are on the map; click one to go back to them
	await _press("Tile_" + _node(town.start_place()))
	t.check(_find("Person_" + target) != null, "someone you met is not marked on the map")
	await _press("Person_" + target)
	t.eq(town.at(), target_place, "clicking a person did not walk to them")
	t.check(scr.view == "talk" and scr.talking == target, "clicking a person did not start a conversation")

	# --- the tablet
	await _press("TabletButton")
	t.check(scr.tablet.visible, "the tablet did not open")
	await _layout("tablet, case notes")
	await _press("TabletNav_notebook")
	scr.tablet.add_note("The timing of all this bothers me.", engine.data["hook"]["window"][0])
	await _frames(1)
	t.check(engine.entry("N1").get("text", "") == "The timing of all this bothers me.", "note not saved")
	await _layout("tablet, notebook")

	# --- evidence management: one-click markers, a Hobby Detective check, ignore and review
	var said := ""
	var other := ""
	for e in engine.state["entries"]:
		if e["source"] == "statement":
			if said == "":
				said = String(e["id"])
			elif other == "":
				other = String(e["id"])
	t.check(said != "" and other != "", "need two statements to sort")
	await _press("Status_%s_suspicious" % said)
	t.eq(engine.status_of(said), "suspicious", "one click did not mark it suspicious")
	t.check(_find("Check_" + said) != null, "no check offered for a suspicious statement")
	await _press("Check_" + said)
	t.check(engine.state["checks"].has(said), "the check was not made")
	var answer := _close_popup()
	t.check(answer.to_lower().contains("connected to the incident") or answer.to_lower().contains("can't be settled"),
			"the check did not answer in a popup: '%s'" % answer)
	for word in ["guilty", "culprit", "lied", "lying", "the truth is"]:
		t.check(not answer.to_lower().contains(word), "the check answer talks about '%s'" % word)
	t.check(_find("Verdict_" + said) != null, "the verdict is not shown on the card")
	t.check(String(_find("ModeLabel").text).begins_with("Hobby Detective"), "mode not shown on the tablet")
	await _press("Status_%s_ignored" % other)
	t.eq(engine.status_of(other), "ignored", "one click did not ignore it")
	t.check(_find("Entry_" + other) == null, "an ignored entry still shows in the notebook")
	await _press("StatusFilter_ignored")
	t.check(_find("Entry_" + other) != null and _find("IgnoredNotice") != null, "Review ignored does not show it")
	await _layout("tablet, review ignored")
	await _press("Restore_" + other)
	t.eq(engine.status_of(other), "", "Restore did not bring it back")
	t.check(_find("Entry_" + other) == null, "a restored entry still shows under Review ignored")
	await _press("StatusFilter_all")
	t.check(_find("Entry_" + other) != null, "a restored entry is missing from Everything")
	await _press("Status_%s_ignored" % other)
	t.check(_find("Entry_" + other) == null, "Everything shows ignored entries")
	await _press("Status_%s_active" % said)
	await _press("Status_%s_suspicious" % said)
	t.eq(engine.status_of(said), "suspicious", "switching status did not stick")
	await _press("TabletNav_evidence")
	t.check(_find("GoToBook_" + book) != null, "a book you asked for is not listed with its place")
	await _layout("tablet, evidence")
	await _press("TabletNav_people")
	await _press("Dir_" + target)
	await _layout("tablet, people")
	t.check(scr.tablet.find_child("Topic_whereabouts", true, false) == null,
			"the tablet lets you question someone remotely")
	await _press("TabletNav_timeline")
	t.check(_find("TimelineChart") != null, "timeline chart missing")
	await _layout("tablet, timeline")
	var timed := ""
	for e in engine.timeline()["entries"]:
		if engine.status_of(String(e["id"])) == "":
			timed = String(e["id"])
			break
	if timed != "":
		await _press("Status_%s_active" % timed)
		t.eq(engine.status_of(timed), "active", "marking from the timeline did not work")
	var credits := int(engine.state["credits"])
	await _press("TabletNav_hints")
	scr.tablet.buy_hint()   # the confirmation dialog is bypassed by calling the action it confirms
	await _frames(1)
	t.check(int(engine.state["credits"]) < credits, "hint did not cost credits")
	await _layout("tablet, hints")

	# --- other case files are listed but can never be opened from here
	await _press("TabletNav_files")
	t.check(_find("ActiveCaseFile") != null, "the open case is not on the tablet")
	var locked := 0
	for e in main.library.entries:
		if e["case_id"] == entry["case_id"]:
			continue
		var f = _find("CaseFile_" + e["case_id"])
		t.check(f != null, "case file %s not listed" % e["case_id"])
		if f != null:
			locked += 1
			t.check(f.disabled, "case file %s can be clicked" % e["case_id"])
			t.check(f.get_signal_connection_list("pressed").is_empty(), "case file %s is wired to something" % e["case_id"])
			f.pressed.emit()
			await _frames(1)
	t.eq(locked, main.library.entries.size() - 1, "every other case is listed, locked")
	t.check(main.current == "investigation" and main.engine.case_id == entry["case_id"], "a locked case file opened")
	t.eq(main.saves.list_saves().size(), 1, "another case was started")
	await _layout("tablet, case files")

	# --- 'Go to' in the people directory walks you there and closes the tablet
	scr.close_tablet()
	scr.go_to(town.start_place())
	scr.open_tablet("people")
	await _frames(1)
	await _press("Dir_" + target)
	await _press("FindPerson_" + target)
	t.check(not scr.tablet.visible, "Go to did not put the tablet away")
	t.eq(town.at(), target_place, "Go to did not walk to the person")
	t.check(scr.view == "talk", "Go to did not start a conversation with someone who is there")

	# --- the T key opens and closes the tablet
	var key := InputEventKey.new()
	key.keycode = KEY_T
	key.pressed = true
	scr._unhandled_input(key)
	t.check(scr.tablet.visible, "T did not open the tablet")
	scr._unhandled_input(key)
	t.check(not scr.tablet.visible, "T did not close the tablet")
	t.eq(Verdict.unseal_count, sealed_before, "the truth was opened during play")

	# --- leave and resume, exactly where you were
	await _press("TabletButton")
	await _press("TabletNav_evidence")
	await _press("MenuButton")
	t.check(main.current == "menu", "Menu button did not return to the main menu")
	var cont = _find("ContinueButton")
	t.check(cont != null and not cont.disabled, "Continue not offered")
	var entries_before: int = engine.state["entries"].size()
	await _press("ContinueButton")
	t.check(main.current == "investigation", "Continue did not reopen the case")
	scr = main.screen
	t.eq(main.engine.state["entries"].size(), entries_before, "progress lost on resume")
	t.eq(scr.town.at(), target_place, "position in town lost on resume")
	t.check(scr.tablet.visible and scr.tablet.page == "evidence", "the open tablet page was not restored")
	t.check(main.engine.state["ui"]["dialogue"].get(target, []).size() >= 2, "conversation lost on resume")
	t.check(scr.town.whereabouts(target) == target_place, "people you have seen were forgotten")
	t.eq(main.engine.status_of(said), "suspicious", "statuses lost on resume")
	t.eq(main.engine.status_of(other), "ignored", "ignored entries lost on resume")
	t.check(main.engine.state["checks"].has(said), "the check was lost on resume")
	t.eq(main.engine.mode(), "hobby", "mode lost on resume")

	# --- solve
	await _press("TabletNav_theory")
	t.check(_find("SubmitTheoryButton") != null, "theory form missing")
	await _layout("tablet, theory")
	var cite = _find("TheoryCite_S1")
	if cite != null:
		cite.button_pressed = true
		cite.toggled.emit(true)
	scr.tablet.submit_from_form()
	await _frames(2)
	t.check(main.current == "reveal", "the truth was not revealed after submitting")
	t.check(Verdict.unseal_count == sealed_before + 1, "the seal was not opened exactly once at the reveal")
	var score = _find("ScoreTotal")
	t.check(score != null and String(score.text).begins_with("Score:"), "score missing on the reveal")
	var narrative = _find("Narrative")
	t.check(narrative != null and String(narrative.text) != "", "narrative missing on the reveal")
	t.check(main.engine.state["revealed"], "case not closed")
	await _layout("reveal")

	# --- a closed case reopens straight to its reveal
	await _press("RevealMenuButton")
	t.check(_find("ContinueButton").disabled, "Continue offered for a closed case")
	main.open_case(entry, false)
	await _frames(1)
	t.check(main.current == "reveal", "closed case did not reopen to the truth")

	# --- settings, then every screen again at the largest text size
	main.show_settings()
	await _frames(1)
	await _layout("settings")
	main.change_setting("text_size", 3)
	main.change_setting("high_contrast", true)
	t.eq(main.theme.default_font_size, 25, "text size not applied")
	_resize(Vector2(1280, 800))
	await _layout("settings, extra large text")
	main.show_load()
	await _layout("load case, extra large text")
	var second: Dictionary = main.library.entries[1]
	main.open_case(second, true)
	await _frames(1)
	t.check(main.current == "investigation", "second case did not open")
	var s2 = main.screen
	var town2 = s2.town
	await _layout("town, extra large text")
	for p in town2.places():
		if not town2.people_at(p["id"]).is_empty():
			s2.go_to(p["id"])
			break
	var who: String = town2.people_here()[0] if not town2.people_here().is_empty() else ""
	if who != "":
		s2.talk_to(who)
		s2.ask(who, "whereabouts")
		s2.ask(who, "incident")
		await _layout("conversation, extra large text")
		s2.back_to_place()
		s2.look_around()
		await _layout("place, extra large text")
	var books2: Array = s2.engine.data["records"].keys()
	books2.sort()
	s2.route_to_book(books2[0])
	s2.read_book(books2[0])
	await _layout("record book, extra large text")
	for pg in ["case", "notebook", "evidence", "people", "timeline", "theory", "hints", "files"]:
		s2.open_tablet(pg)
		await _layout("tablet %s, extra large text" % pg)
	s2.close_tablet()
	main.show_main_menu()
	await _layout("main menu, extra large text")

	# every bundled town is drawn, in normal and in high-contrast colours
	main.change_setting("text_size", 1)
	_resize(Vector2(960, 640))
	var hc := false
	for e in main.library.entries:
		main.change_setting("high_contrast", hc)
		main.open_case(e, true)
		await _layout("town of %s%s" % [e["case_id"], " (high contrast)" if hc else ""])
		t.eq(main.screen.map.get_child_count() >= main.engine.data["places"].size(), true, "buildings missing")
		hc = not hc
	main.show_main_menu()
	main.change_setting("text_size", 1)
	main.change_setting("high_contrast", false)
	main.saves.reset_all()
	main.queue_free()
	await _frames(1)
	t.end()


static func _node(pid: String) -> String:
	return pid.replace(":", "_")


func _resize(to: Vector2) -> void:
	main.anchor_right = 0.0
	main.anchor_bottom = 0.0
	main.position = Vector2.ZERO
	main.size = to


func _layout(where: String) -> void:
	## Headless Godot still lays out Controls, so the sizes are real: nothing squeezed, collapsed,
	## overlapping on the map, or off screen.
	await _frames(2)
	var view: Vector2 = main.size
	var problems := []
	_walk(main.screen, view, problems)
	var map = main.screen.find_child("TownMap", true, false) if main.screen != null else null
	var tablet = main.screen.find_child("Tablet", true, false) if main.screen != null else null
	if map != null and map.is_visible_in_tree():
		var side = main.screen.find_child("LocationPanel", true, false)
		if map.size.y < 300 or map.size.x < 300:
			problems.append("the town map is only %dx%d" % [int(map.size.x), int(map.size.y)])
		if side != null and side.size.y < 300:
			problems.append("the location panel is only %d px tall" % int(side.size.y))
	if map != null and map.is_visible_in_tree() and (tablet == null or not tablet.visible):
		var rects := []
		for c in map.get_children():
			if c is Button:
				rects.append([String(c.name), c.get_rect()])
				if not Rect2(Vector2.ZERO, map.size).encloses(c.get_rect()):
					problems.append("%s sticks out of the town map" % c.name)
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				if rects[i][1].intersects(rects[j][1]):
					problems.append("%s overlaps %s on the map" % [rects[i][0], rects[j][0]])
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


func _close_popup() -> String:
	## Read the open message popup and dismiss it with OK, as a player would. Returns "title | text".
	for c in main.get_children():
		if c is AcceptDialog and c.visible:
			var said: String = "%s | %s" % [c.title, c.dialog_text]
			c.hide()
			c.confirmed.emit()
			return said
	return ""


func _press(node_name: String) -> void:
	var b = _find(node_name)
	t.check(b != null, "button %s not found on screen '%s'" % [node_name, main.current])
	if b != null:
		b.pressed.emit()
	await _frames(1)
