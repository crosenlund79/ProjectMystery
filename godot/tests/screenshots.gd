## Runs the real game with rendering on and saves screenshots of the main screens (CI, under a virtual
## display):  godot --path godot --rendering-driver opengl3 -s res://tests/screenshots.gd -- --out=<folder>
extends SceneTree

var out := "user://shots"
var main


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	main = load("res://scenes/main.tscn").instantiate()
	main.user_root = "user://shots/"
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(out.path_join(name + ".png"))
	print("shot %s %s %dx%d" % [name, "ok" if err == OK else "FAILED", img.get_width(), img.get_height()])


func _run() -> void:
	await process_frame
	main.saves.reset_all()
	main.show_intro()
	await create_timer(1.3).timeout
	await _shot("01_opening_1")
	main.screen.next()
	await create_timer(1.3).timeout
	await _shot("02_opening_2")
	main.screen.next()
	main.screen.next()
	await create_timer(1.3).timeout
	await _shot("03_opening_4")
	main.change_setting("intro_seen", true)
	main.show_main_menu()
	await _shot("04_menu")
	main.change_setting("mode", "beginner")
	main.show_new_case()
	await _shot("05_new_case")
	var entry: Dictionary = main.library.entries[0]
	for e in main.library.entries:
		if e["case_id"] == "2-crisis-60d-r10-I3":
			entry = e
	main.open_case(entry, true)
	await _shot("06_town")
	var scr = main.screen
	var engine = main.engine
	var town = scr.town
	var target := ""
	for p in town.places():
		for rid in town.people_at(p["id"]):
			if target == "" and engine.data["testimony"].has(rid):
				target = rid
				scr.go_to(p["id"])
	await _shot("07_place")
	if target != "":
		scr.talk_to(target)
		scr.ask(target, "whereabouts")
		scr.ask(target, "money")
		await _shot("08_conversation")
		scr.ask(target, "window", true)
		await _shot("09_conversation_pressed")
	for r in engine.data["residents"]:
		if r["condition"] != "deceased":
			for tp in ["whereabouts", "window", "incident"]:
				engine.ask(r["id"], tp)
				engine.ask(r["id"], tp, false, "more")
	scr.back_to_place()
	await _shot("10_intuition")
	scr.open_tablet("notebook")
	await _shot("11_notebook_intuition")
	scr.open_tablet("timeline")
	await _shot("12_timeline_contradictions")
	scr.open_tablet("people")
	await _shot("13_people")
	scr.close_tablet()
	var homes := 0
	for p in town.places():
		if p["kind"] == "home" and homes < 2:
			scr.go_to(p["id"])
			homes += 1
			await _shot("14_house_%d" % homes)
	for k in ["pub", "mill", "workshop"]:
		for p in town.places():
			if p["kind"] == k:
				scr.go_to(p["id"])
				await _shot("15_%s" % k)
				break
	main.show_main_menu()
	await process_frame
	quit(0)
