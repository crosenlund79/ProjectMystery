## The case importer, with the ten import-test cases in <repository>/import-test-cases (not bundled, not
## registered): none is in the library before importing; each goes in through the game's own import
## (main.import_case, what the file dialog calls), validates, is listed, opens and can be played.
extends RefCounted

const ROOT := "user://test_import/"

var t
var tree: SceneTree
var main


func run(t_, tree_: SceneTree) -> void:
	t = t_
	tree = tree_
	t.begin("ten import-test cases go in through the importer and play")
	var folder := ProjectSettings.globalize_path("res://") + "../import-test-cases/"
	var files := []
	var dir := DirAccess.open(folder)
	t.check(dir != null, "no import-test-cases folder next to the project")
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".mcase"):
				files.append(folder + f)
	files.sort()
	t.eq(files.size(), 10, "import-test cases")
	main = load("res://scenes/main.tscn").instantiate()
	main.user_root = ROOT
	tree.root.add_child(main)
	await tree.process_frame
	main.saves.reset_all()
	_clear_imported()
	var bundled: int = main.library.entries.size()
	var before := {}
	for e in main.library.entries:
		before[e["case_id"]] = true
	for path in files:
		var id := String(path).get_file().get_basename()
		t.check(not before.has(id), "%s was in the library before it was imported" % id)
		var res: Dictionary = main.import_case(path)
		_close_popups()
		t.check(res["ok"], "%s did not import: %s" % [id, res.get("errors", [])])
		t.eq(res["case_id"], id, "imported under another name")
	t.eq(main.library.entries.size(), bundled + files.size(), "the library does not list every imported case")
	var opened := 0
	for e in main.library.entries:
		if before.has(e["case_id"]):
			continue
		var loaded: Dictionary = main.library.load_package(e)
		t.check(loaded["ok"], "%s does not load after import" % e["case_id"])
		if opened < 3 and main.open_case(e, true):
			await tree.process_frame
			t.eq(main.current, "investigation", "%s did not open" % e["case_id"])
			var eng = main.engine
			var r: Dictionary = {}
			for x in eng.data["residents"]:
				if x["condition"] != "deceased" and r.is_empty():
					r = x
			var ans: Dictionary = eng.ask(r["id"], "whereabouts")
			t.check(not ans.has("error") and not ans["lines"].is_empty(), "%s: nobody answers" % e["case_id"])
			opened += 1
	t.eq(opened, 3, "imported cases opened")
	# a broken file is refused with a reason, not imported
	var bad := ROOT + "broken.mcase"
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{\"format\": \"project-mystery-case\", \"format_version\": 1}")
	f.close()
	var refused: Dictionary = main.import_case(ProjectSettings.globalize_path(bad))
	_close_popups()
	t.check(not refused["ok"] and not refused["errors"].is_empty(), "a broken file was imported")
	main.show_main_menu()
	_clear_imported()
	main.saves.reset_all()
	main.queue_free()
	await tree.process_frame
	t.end()


func _clear_imported() -> void:
	## This test's own user folder only: remove what earlier runs imported.
	var d := DirAccess.open(main.library.user_cases)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".mcase"):
				d.remove(f)
	main.library.refresh()


func _close_popups() -> void:
	for c in main.get_children():
		if c is AcceptDialog and c.visible:
			c.hide()
			c.confirmed.emit()
