## Replaceable artwork (scripts/core/art.gd): templates, same-named replacements, graceful fallbacks, and
## art for everyone and everywhere in every bundled case.
extends RefCounted

const ArtLib = preload("res://scripts/core/art.gd")
const CaseLibrary = preload("res://scripts/core/case_library.gd")
const Expression = preload("res://scripts/core/expression.gd")

const ROOT := "user://test_art/"


func run(t, _tree) -> void:
	_templates(t)
	_replacements(t)
	_everyone_has_art(t)
	_faces(t)
	ArtLib.extra_roots = []
	ArtLib.clear_cache()


func _templates(t) -> void:
	t.begin("templates: every picture, the opening and the chime are there")
	ArtLib.extra_roots = []
	ArtLib.clear_cache()
	for who in ArtLib.CAST:
		for age in ["younger", "older"]:
			for e in ArtLib.EXPRESSIONS:
				var rel := "portraits/%s/%s_%s" % [who, age, e]
				t.check(ArtLib.texture(rel) != null, "missing template " + rel)
	for style in ArtLib.HOUSE_STYLES:
		for c in ["fine", "tidy", "plain", "worn"]:
			t.check(ArtLib.texture("houses/%s_%s" % [style, c]) != null, "missing house %s %s" % [style, c])
	for k in ["shop", "pub", "mill", "clinic", "workshop", "square", "road"]:
		t.check(ArtLib.texture("places/" + k) != null, "missing place " + k)
	t.check(ArtLib.source_of("places/mill") == "res://art/places/template_mill.png", "templates load from res://art")
	t.check(ArtLib.texture("intro/frame_1") != null and ArtLib.texture("intro/frame_3") != null, "opening frames")
	t.check(ArtLib.lines("intro/captions").size() >= 3, "opening lines")
	t.check(ArtLib.sound("sounds/intuition") != null, "intuition chime")
	t.check(ArtLib.texture("places/nowhere") == null, "a picture that does not exist should be null")
	t.end()


static func _png(path: String, w: int, h: int, c: Color) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	img.save_png(path)


static func _wav(path: String, rate: int) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var data := PackedByteArray()
	data.resize(rate / 10 * 2)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(rate)
	f.store_32(rate * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()


func _replacements(t) -> void:
	t.begin("a same-named file without template_ replaces the template; nothing else changes")
	var over := ROOT + "overrides"
	_png(over + "/portraits/clara/younger_worried.png", 12, 12, Color.RED)
	_png(over + "/houses/vale_tidy.png", 30, 20, Color.BLUE)
	_png(over + "/portraits/zed/younger_neutral.png", 16, 16, Color.GREEN)
	DirAccess.make_dir_recursive_absolute(over + "/intro")
	var cap := FileAccess.open(over + "/intro/captions.txt", FileAccess.WRITE)
	cap.store_string("One.\nTwo.\n")
	cap.close()
	_wav(over + "/sounds/intuition.wav", 11025)
	ArtLib.extra_roots = [over]
	ArtLib.clear_cache()
	var face: Texture2D = ArtLib.texture("portraits/clara/younger_worried")
	t.check(face != null and face.get_width() == 12, "the replacement portrait was not used")
	t.check(ArtLib.source_of("portraits/clara/younger_worried").begins_with(over), "replacement not found first")
	t.check(ArtLib.texture("portraits/clara/younger_happy").get_width() == 256, "a portrait not replaced must stay the template")
	t.check(ArtLib.texture("houses/vale_tidy").get_width() == 30, "the replacement house was not used")
	t.eq(Array(ArtLib.lines("intro/captions")), ["One.", "Two."], "the replacement opening lines")
	var s = ArtLib.sound("sounds/intuition")
	t.check(s is AudioStreamWAV and s.mix_rate == 11025, "the replacement chime was not used")
	t.eq(ArtLib.character("zed"), "zed", "a new character with their own art keeps it")
	var stand_in := ArtLib.character("nobody_we_know")
	t.check(ArtLib.CAST.has(stand_in), "someone without art should get a stand-in face")
	t.eq(ArtLib.character("nobody_we_know"), stand_in, "the stand-in must always be the same")
	t.check(FileAccess.file_exists("res://art/portraits/clara/template_younger_worried.png") or
			ResourceLoader.exists("res://art/portraits/clara/template_younger_worried.png"), "a template was lost")
	# take the replacements away again: back to the templates
	ArtLib.extra_roots = []
	ArtLib.clear_cache()
	t.eq(ArtLib.texture("portraits/clara/younger_worried").get_width(), 256, "the template did not come back")
	t.end()


func _everyone_has_art(t) -> void:
	t.begin("every resident has a face and work clothes, every place a picture, in every bundled case")
	var lib = CaseLibrary.new(ROOT)
	for e in lib.entries:
		var r: Dictionary = lib.load_package(e)
		if not r["ok"]:
			continue
		var inv: Dictionary = r["package"]["investigation"]
		for res in inv["residents"]:
			var layers: Array = ArtLib.portrait(res, "worried")
			t.check(layers[0] != null and layers[1] != null, "%s: %s has no portrait" % [e["case_id"], res["id"]])
			t.check(["cheerful", "easygoing", "brisk", "reserved", "gruff"].has(res.get("demeanour", "")),
					"%s: %s has no demeanour" % [e["case_id"], res["id"]])
		for p in inv["places"]:
			t.check(not ArtLib.place_layers(p).is_empty(), "%s: %s has no picture" % [e["case_id"], p["id"]])
			if p["kind"] == "home":
				var look: Dictionary = p.get("look", {})
				t.check(["fine", "tidy", "plain", "worn"].has(look.get("condition", "")), "%s: no condition" % p["id"])
	t.end()


func _faces(t) -> void:
	t.begin("faces: react to the conversation and the person's manner; harder difficulties show less")
	var calm := {"id": "a", "first": "Ana", "demeanour": "cheerful", "condition": "alive"}
	var pressed := {"pressed": true, "lines": [{"text": "I don't know anything about that.", "notes": []}]}
	t.eq(Expression.react(calm, "nervous", "money", pressed), ["uneasy", 3], "a nervous person pressed")
	t.eq(Expression.react(calm, "smooth", "money", pressed)[0], "guarded", "a smooth person pressed")
	var owes := {"pressed": false, "lines": [{"text": "I'm behind on paying Felix back — 40 crowns.", "notes": ["S1"]}]}
	t.eq(Expression.react(calm, "nervous", "money", owes), ["worried", 1], "their own money troubles")
	var plain := {"pressed": false, "lines": [{"text": "I don't know anything about that.", "notes": []}]}
	t.eq(Expression.react(calm, "nervous", "vehicles", plain), ["content", 0], "nothing in particular")
	t.eq(Expression.shown(calm, ["worried", 1], "beginner"), "worried", "a beginner sees small reactions")
	t.eq(Expression.shown(calm, ["worried", 1], "experienced"), "content", "an experienced detective does not")
	t.eq(Expression.shown(calm, ["uneasy", 3], "experienced"), "uneasy", "strong reactions show to everyone")
	t.check(Expression.caption(calm, "worried", "beginner") != "", "a beginner is told what a face shows")
	t.eq(Expression.caption(calm, "worried", "hobby"), "", "only a beginner is told in words")
	t.end()
