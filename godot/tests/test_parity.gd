## Python vs Godot: replay the scripted investigations recorded by the Python laboratory
## (python -m mystery build-library --parity godot/tests/parity) and require identical results:
## every answer, notebook id, refusal, trace, record, hint, timeline conflict, score and reveal.
extends RefCounted

const CaseFormat = preload("res://scripts/core/case_format.gd")
const Investigation = preload("res://scripts/core/investigation.gd")

const DIR := "res://tests/parity/"


func run(t, _tree) -> void:
	var dir := DirAccess.open(DIR)
	t.begin("parity fixtures exist")
	t.check(dir != null, "no parity folder")
	var files := PackedStringArray()
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".json"):
				files.append(f)
	files.sort()
	t.check(files.size() >= 4, "expected at least 4 parity fixtures, found %d" % files.size())
	t.end()
	for f in files:
		var fx = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		var loaded := CaseFormat.load_file("res://cases/" + String(fx["case_file"]))
		for script in fx["scripts"]:
			t.begin("%s / %s" % [fx["case_file"], script["name"]])
			t.check(loaded["ok"], "case failed to load: %s" % [loaded["errors"]])
			if loaded["ok"]:
				_replay(t, loaded["package"], script)
			t.end()


func _replay(t, pkg: Dictionary, script: Dictionary) -> void:
	var inv = Investigation.new(pkg, null)
	var actions: Array = script["actions"]
	var expected: Array = script["expected"]
	t.eq(actions.size(), expected.size(), "fixture length")
	var matched := 0
	for i in range(actions.size()):
		var a: Dictionary = actions[i]
		var got := _do(inv, a)
		var d: String = t.diff(got, expected[i], "")
		if d != "":
			t.check(false, "step %d (%s): %s" % [i, a["op"], d])
			return
		matched += 1
	t.check(matched == actions.size(), "only %d of %d steps matched" % [matched, actions.size()])


static func _do(inv, a: Dictionary) -> Dictionary:
	match String(a["op"]):
		"ask":
			return inv.ask(a["who"], a["topic"], bool(a.get("press", false)), String(a.get("follow", "")))
		"inspect_place":
			return inv.inspect_place(a["id"])
		"inspect_vehicle":
			return inv.inspect_vehicle(a["id"])
		"read":
			return inv.read(a["book"], a.get("day"))
		"cite":
			return {"op": "cite", "note": inv.cite_record(a["entry"])}
		"note":
			return {"op": "note", "note": inv.note(a["text"], a.get("time"))}
		"mark":
			return {"op": "mark", "ok": inv.mark(a["entry"], a["mark"])}
		"hint":
			return inv.hint()
		"timeline":
			var tl: Dictionary = inv.timeline()
			tl["op"] = "timeline"
			return tl
		"state":
			var st: Dictionary = inv.state
			return {"op": "state", "entries": st["entries"], "credits": st["credits"],
					"hints_bought": st["hints_bought"], "hint_spend": st.get("hint_spend", 0),
					"goodwill": st["goodwill"], "pressed": st["pressed"], "earlier": st["earlier"],
					"concluded": st["concluded"],
					"revealed": st["revealed"]}
		"submit":
			return inv.submit(a["mechanism"], a["responsible"], a["motive"], a["cites"], a["summary"])
		"giveup":
			return inv.give_up()
		"reveal":
			return inv.reveal()
	return {"op": a["op"], "error": "unknown op"}
