## Self-check for an exported build:  ProjectMystery.exe --headless -- --smoke-test=<report path>
## Loads every bundled case, walks its town (every place, the people there, the records kept
## there), and proves the truth stays sealed until the case is concluded, then opens. Reports only case ids and OK/FAIL - never case content.
extends RefCounted

const CaseLibrary = preload("res://scripts/core/case_library.gd")
const Investigation = preload("res://scripts/core/investigation.gd")
const Verdict = preload("res://scripts/core/verdict.gd")
const Town = preload("res://scripts/core/town.gd")
const CaseFormat = preload("res://scripts/core/case_format.gd")


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
		var town = Town.new(inv)
		var before: int = Verdict.unseal_count
		var met := 0
		for p in town.places():
			town.go(p["id"])
			town.look_around()
			for rid in town.people_here():
				if met < 4 and not town.ask(rid, "window").has("error"):
					met += 1
			for b in town.records_at(p["id"]):
				town.read(b)
			for vid in town.vehicles_at(p["id"]):
				town.examine(vid)
		var opened := 0
		for rid in inv.data["testimony"]:
			for it in inv.data["testimony"][rid]["items"]:
				if CaseFormat.REL_VALUES.has(CaseFormat.open_relevance(loaded["package"], it["key"])):
					opened += 1
		if opened == 0:
			ok = false
			lines.append("FAIL %s: no evidence check opens" % e["case_id"])
			continue
		if met == 0:
			ok = false
			lines.append("FAIL %s: nobody could be found in town" % e["case_id"])
			continue
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
