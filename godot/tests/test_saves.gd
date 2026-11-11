## Save and resume without losing progress; settings; nothing from the truth in a save.
extends RefCounted

const CaseLibrary = preload("res://scripts/core/case_library.gd")
const SaveStore = preload("res://scripts/core/save_store.gd")
const Investigation = preload("res://scripts/core/investigation.gd")


func run(t, _tree) -> void:
	var root := "user://test_saves/"
	var store = SaveStore.new(root)
	store.reset_all()
	var lib = CaseLibrary.new(root)
	var pkg: Dictionary = lib.load_package(lib.entries[0])["package"]

	t.begin("an investigation survives save and load exactly")
	var inv = Investigation.new(pkg, null)
	var rid := ""
	for r in pkg["investigation"]["residents"]:
		if r["condition"] != "deceased" and rid == "":
			rid = r["id"]
	inv.ask(rid, "whereabouts")
	inv.ask(rid, "window", true)
	for pl in pkg["investigation"]["places"]:
		inv.inspect_place(pl["id"])
	inv.note("Something odd about the back door.", 1440 * 3 + 600)
	inv.hint()
	inv.state["ui"]["dialogue"] = {rid: [{"q": "Where were you?", "topic": "whereabouts", "pressed": false, "lines": []}]}
	if not inv.state["entries"].is_empty():
		inv.mark(inv.state["entries"][0]["id"], "disputed")
	t.check(store.save(inv.state), "save failed")
	var loaded = store.load_state(pkg["case_id"])
	t.check(loaded != null, "save could not be read back")
	var again = Investigation.new(pkg, loaded)
	t.eq(again.state["entries"], inv.state["entries"], "notebook")
	t.eq(again.state["credits"], inv.state["credits"], "credits")
	t.eq(again.state["goodwill"], inv.state["goodwill"], "patience")
	t.eq(again.state["pressed"], inv.state["pressed"], "pressed topics")
	t.eq(again.state["ui"]["dialogue"], inv.state["ui"]["dialogue"], "conversation history")
	t.check(typeof(again.state["credits"]) == TYPE_INT, "credits came back as a float")
	var n_before: int = again.state["entries"].size()
	var note_id: String = again.note("after loading")
	t.eq(note_id, "N2", "numbering continues after loading")
	t.eq(again.state["entries"].size(), n_before + 1, "new entry appended")
	t.end()

	t.begin("a save never contains the truth")
	var text := FileAccess.get_file_as_string(store.save_path(pkg["case_id"]))
	for forbidden in ["sealed_truth", "testimony_audit", "narrative", "private_states"]:
		t.check(not text.contains(forbidden), "save contains %s" % forbidden)
	t.end()

	t.begin("a save for another case is ignored")
	var other: Dictionary = lib.load_package(lib.entries[1])["package"]
	var wrong = Investigation.new(other, loaded)
	t.eq(wrong.state["entries"].size(), 0, "foreign save applied")
	t.end()

	t.begin("saves are listed newest first and can be deleted")
	var inv2 = Investigation.new(other, null)
	inv2.note("second case")
	store.save(inv2.state)
	var list: Array = store.list_saves()
	t.eq(list.size(), 2, "two saves")
	t.eq(list[0]["case_id"], other["case_id"], "newest first")
	store.delete_save(other["case_id"])
	t.eq(store.list_saves().size(), 1, "deleted")
	t.end()

	t.begin("settings round-trip and stay in range")
	store.save_settings({"text_size": 3, "high_contrast": true, "fullscreen": false})
	var s: Dictionary = store.load_settings()
	t.eq(s, {"text_size": 3, "high_contrast": true, "fullscreen": false}, "settings")
	store.save_settings({"text_size": 99})
	t.eq(store.load_settings()["text_size"], 3, "text size clamped")
	store.save_settings({"text_size": 1, "high_contrast": false, "fullscreen": false})
	t.end()
