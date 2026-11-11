## Case loading: the bundled library, validation, rejection of bad files, the seal.
extends RefCounted

const CaseFormat = preload("res://scripts/core/case_format.gd")
const CaseLibrary = preload("res://scripts/core/case_library.gd")


func run(t, _tree) -> void:
	var lib = CaseLibrary.new("user://test_format/")

	t.begin("the bundled library loads and every case validates")
	t.check(lib.entries.size() >= 10, "expected at least 10 bundled cases, found %d" % lib.entries.size())
	t.check(lib.problems.is_empty(), "library problems: %s" % [lib.problems])
	for e in lib.entries:
		var r: Dictionary = lib.load_package(e)
		t.check(r["ok"], "%s failed to load: %s" % [e["case_id"], r["errors"]])
	t.end()

	t.begin("the library index shows only spoiler-free summaries")
	for e in lib.entries:
		var keys: Array = e.keys()
		keys.sort()
		t.eq(keys, ["case_id", "difficulty", "path", "season", "sha256", "source", "start_label", "title", "town"],
				"index fields")
	t.end()

	var base: Dictionary = lib.load_package(lib.entries[0])["package"]

	t.begin("bad files are rejected with a readable reason")
	var cases := {
		"wrong format": func(p): p["format"] = "something-else",
		"future version": func(p): p["format_version"] = 2,
		"truth field leaked": func(p): _first_item(p)["lie"] = true,
		"event id leaked": func(p): _first_item(p)["text"] = "see E000123",
		"missing window": func(p): p["investigation"]["hook"].erase("window"),
		"unknown topic": func(p): _first_item(p)["topics"].append("secrets"),
		"unknown resident": func(p): _first_item(p)["about"].append("nobody"),
		"corrupted seal": func(p): p["sealed_truth"]["data"] = "AAAA" + String(p["sealed_truth"]["data"]).substr(4),
		"bad style": func(p): p["investigation"]["testimony"][p["investigation"]["testimony"].keys()[0]]["style"] = "shifty",
	}
	for name in cases:
		var broken: Dictionary = base.duplicate(true)
		cases[name].call(broken)
		t.check(not CaseFormat.validate(broken).is_empty(), "%s was accepted" % name)
	t.check(not CaseFormat.parse_text("{not json").get("ok", true), "invalid JSON accepted")
	t.check(not CaseFormat.parse_text("").get("ok", true), "empty file accepted")
	t.check(not CaseFormat.load_file("res://cases/does-not-exist.mcase")["ok"], "missing file accepted")
	t.end()

	t.begin("the seal opens only with the right case id and intact data")
	var sealed: Dictionary = base["sealed_truth"]
	var opened := CaseFormat.unseal(sealed, base["case_id"])
	t.check(opened["ok"], "unseal failed: %s" % opened.get("error"))
	if opened["ok"]:
		t.eq(opened["truth"]["case_id"], base["case_id"], "truth case id")
		var narrative: String = opened["truth"]["narrative"]
		t.check(not JSON.stringify(base["investigation"]).contains(narrative), "narrative visible in the player view")
		t.check(not String(sealed["data"]).contains(narrative.left(12)), "narrative visible in the sealed data")
	t.check(not CaseFormat.unseal(sealed, "some-other-case")["ok"], "opened with the wrong case id")
	var tampered: Dictionary = sealed.duplicate()
	tampered["plain_sha256"] = "0".repeat(64)
	t.check(not CaseFormat.unseal(tampered, base["case_id"])["ok"], "opened despite a checksum mismatch")
	t.end()

	t.begin("an imported case file is validated and added to the library")
	var src := "user://test_format/import_me.mcase"
	var f := FileAccess.open(src, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(lib.entries[0]["path"]))
	f.close()
	var r: Dictionary = lib.import_file(src)
	t.check(r["ok"], "import failed: %s" % [r["errors"]])
	var junk := "user://test_format/junk.mcase"
	var g := FileAccess.open(junk, FileAccess.WRITE)
	g.store_string("{\"format\": \"nope\"}")
	g.close()
	t.check(not lib.import_file(junk)["ok"], "junk import accepted")
	t.end()


static func _first_item(p: Dictionary) -> Dictionary:
	var testimony: Dictionary = p["investigation"]["testimony"]
	for rid in testimony:
		if not testimony[rid]["items"].is_empty():
			return testimony[rid]["items"][0]
	return {}
