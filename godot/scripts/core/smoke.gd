## Self-check for an exported build:  ProjectMystery.exe --headless -- --smoke-test=<report path>
## Loads every bundled case, plays a little of each, and proves the truth stays sealed until the
## case is concluded, then opens. Reports only case ids and OK/FAIL - never case content.
extends RefCounted

const CaseLibrary = preload("res://scripts/core/case_library.gd")
const Investigation = preload("res://scripts/core/investigation.gd")
const Verdict = preload("res://scripts/core/verdict.gd")


static func run(out_path: String) -> int:
	var lines := PackedStringArray()
	var ok := true
	var lib = CaseLibrary.new("user://smoke/")
	if lib.entries.is_empty():
		ok = false
		lines.append("FAIL no bundled cases found")
	for e in lib.entries:
		var loaded: Dictionary = lib.load_package(e)
		if not loaded["ok"]:
			ok = false
			lines.append("FAIL %s does not load: %s" % [e["case_id"], loaded["errors"][0]])
			continue
		var inv = Investigation.new(loaded["package"], null)
		var before: int = Verdict.unseal_count
		var people: Array = inv.data["residents"]
		for i in range(mini(3, people.size())):
			inv.ask(people[i]["id"], "window")
		for p in inv.data["places"]:
			inv.inspect_place(p["id"])
		for b in inv.data["records"]:
			inv.read(b)
		inv.hint()
		var early: Dictionary = inv.reveal()
		if not early["sealed"] or Verdict.unseal_count != before:
			ok = false
			lines.append("FAIL %s: the truth opened before the case was concluded" % e["case_id"])
			continue
		inv.give_up()
		var res: Dictionary = inv.reveal()
		if res["sealed"] or res["model"] == null:
			ok = false
			lines.append("FAIL %s: the truth would not open after concluding" % e["case_id"])
			continue
		lines.append("OK %s (%d notebook entries)" % [e["case_id"], inv.state["entries"].size()])
	lines.append("SMOKE %s %d cases" % ["OK" if ok else "FAILED", lib.entries.size()])
	var text := "\n".join(lines) + "\n"
	print(text)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	return 0 if ok else 1
