## Replaceable artwork (see res://art/README.md).
##
## Every picture, text and sound the game shows has a template made for it:
##     res://art/<folder>/template_<name>.png   (.txt for text, .wav for sounds)
## A file with the same name without "template_" replaces it, from the first of these that has one:
##     <the folder ProjectMystery.exe is in>/art/<folder>/<name>.png   (just copy files there)
##     user://art/<folder>/<name>.png                                  (the game's user folder)
##     res://art/<folder>/<name>.png                                   (in the project, in the Godot editor)
## Pictures may be .png, .jpg, .jpeg, .webp or .svg. A missing replacement falls back to the template, and a
## missing template to the game's own drawing, so no code changes are ever needed.
extends RefCounted

const EXTS := ["png", "jpg", "jpeg", "webp", "svg"]
const CAST := ["agnes", "anton", "arvid", "bruno", "clara", "daniel", "elias", "emil", "felix", "greta", "hedda",
		"henrik", "ida", "jonas", "lena", "margaret", "marta", "nora", "oskar", "ruth", "selma", "tomas", "vera",
		"viktor"]
const HOUSE_STYLES := ["ash", "brandt", "carver", "dunmore", "harrow", "holm", "kessler", "lind", "morrow",
		"okafor", "pryce", "vale"]
const EXPRESSIONS := ["neutral", "happy", "content", "tired", "worried", "uneasy", "guarded", "irritated"]
const AGE := {"young adult": "younger", "adult": "younger", "middle-aged": "older", "older": "older"}
const ROLE_OF := {"mill hand": "mill_hand", "mill owner": "mill_owner", "grocer": "grocer",
		"shop assistant": "shop_assistant", "publican": "publican", "barhand": "barhand", "nurse": "nurse",
		"mechanic": "mechanic", "out of work": "unemployed", "retired": "retiree"}

## Extra folders to look in first (tests use this; players use the folders above).
static var extra_roots: Array = []
static var _cache := {}


static func roots() -> Array:
	var out := extra_roots.duplicate()
	out.append(OS.get_executable_path().get_base_dir().path_join("art"))
	out.append("user://art")
	return out


static func clear_cache() -> void:
	_cache.clear()


static func source_of(rel: String) -> String:
	## Where a picture comes from: a replacement's path, the template's path, or "" if neither exists.
	var dir := rel.get_base_dir()
	var file := rel.get_file()
	for root in roots():
		for ext in EXTS:
			var p: String = String(root).path_join("%s.%s" % [rel, ext])
			if FileAccess.file_exists(p):
				return p
	for ext in EXTS:
		var p := "res://art/%s.%s" % [rel, ext]
		if ResourceLoader.exists(p):
			return p
	var t := "res://art/%s/template_%s.png" % [dir, file]
	if ResourceLoader.exists(t):
		return t
	return ""


static func texture(rel: String) -> Texture2D:
	## The picture for e.g. "portraits/clara/younger_worried", or null.
	if _cache.has(rel):
		return _cache[rel]
	var tex: Texture2D = null
	var src := source_of(rel)
	if src.begins_with("res://"):
		var res = load(src)
		if res is Texture2D:
			tex = res
	elif src != "":
		var img := Image.load_from_file(src)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	_cache[rel] = tex
	return tex


static func lines(rel: String) -> PackedStringArray:
	## The lines of a replaceable text, e.g. "intro/captions".
	var paths := []
	for root in roots():
		paths.append(String(root).path_join(rel + ".txt"))
	paths.append("res://art/%s.txt" % rel)
	paths.append("res://art/%s/template_%s.txt" % [rel.get_base_dir(), rel.get_file()])
	for p in paths:
		if FileAccess.file_exists(p):
			var out := PackedStringArray()
			for line in FileAccess.get_file_as_string(p).split("\n"):
				if line.strip_edges() != "":
					out.append(line.strip_edges())
			return out
	return PackedStringArray()


static func sound(rel: String) -> AudioStream:
	## A sound, e.g. "sounds/intuition": a replacement .wav (16-bit PCM) or the template.
	var key := "sound:" + rel
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = null
	for root in roots():
		var p: String = String(root).path_join(rel + ".wav")
		if FileAccess.file_exists(p):
			s = _wav(p)
			if s != null:
				break
	if s == null:
		for p in ["res://art/%s.wav" % rel, "res://art/%s/template_%s.wav" % [rel.get_base_dir(), rel.get_file()]]:
			if ResourceLoader.exists(p):
				s = load(p)
				break
	_cache[key] = s
	return s


static func _wav(path: String) -> AudioStreamWAV:
	## Reads an uncompressed 16-bit PCM .wav file (what most editors save by default).
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != "RIFF":
		return null
	f.get_32()
	if f.get_buffer(4).get_string_from_ascii() != "WAVE":
		return null
	var channels := 1
	var rate := 22050
	var bits := 16
	var data := PackedByteArray()
	while f.get_position() + 8 <= f.get_length():
		var id := f.get_buffer(4).get_string_from_ascii()
		var size := f.get_32()
		if id == "fmt ":
			var fmt := f.get_16()
			channels = f.get_16()
			rate = f.get_32()
			f.get_32()
			f.get_16()
			bits = f.get_16()
			if fmt != 1:
				return null
			f.seek(f.get_position() + size - 16)
		elif id == "data":
			data = f.get_buffer(size)
		else:
			f.seek(f.get_position() + size + (size % 2))
	if bits != 16 or data.is_empty():
		return null
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = channels == 2
	s.data = data
	return s


# --------------------------------------------------------------------------- people
static func character(rid: String) -> String:
	## Whose face a resident wears: their own if there is art for them, else a stand-in chosen from their id
	## (so a case with new names still gives everyone a face of their own).
	if CAST.has(rid) or texture("portraits/%s/younger_neutral" % rid) != null:
		return rid
	return CAST[absi(hash(rid)) % CAST.size()]


static func role_of(resident: Dictionary) -> String:
	if resident.has("role") and resident["role"] != null:
		return String(resident["role"])
	var occ := String(resident.get("occupation", ""))
	for k in ROLE_OF:
		if occ.begins_with(k):
			return ROLE_OF[k]
	return "unemployed"


static func portrait(resident: Dictionary, expression := "neutral") -> Array:
	## [head, clothes] textures for a resident with an expression (either may be null).
	var who := character(String(resident.get("id", "")))
	var age: String = AGE.get(String(resident.get("age_group", "adult")), "younger")
	var head := texture("portraits/%s/%s_%s" % [who, age, expression])
	if head == null:
		head = texture("portraits/%s/%s_neutral" % [who, age])
	return [head, texture("clothes/" + role_of(resident))]


# --------------------------------------------------------------------------- places
static func slug(text: String) -> String:
	var s := text.to_lower().replace("'", "")
	if s.begins_with("the "):
		s = s.substr(4)
	var out := ""
	for ch in s:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return out


static func place_layers(place: Dictionary) -> Array:
	## [[texture, mirrored], ...] from back to front; empty if there is no art for the place.
	var kind := String(place.get("kind", ""))
	var out := []
	if kind == "home":
		var look: Dictionary = place.get("look", {})
		var style := String(look.get("style", ""))
		if not HOUSE_STYLES.has(style) and texture("houses/%s_tidy" % style) == null:
			style = HOUSE_STYLES[absi(hash(String(place.get("id", "")))) % HOUSE_STYLES.size()]
		var base := texture("houses/%s_%s" % [style, String(look.get("condition", "tidy"))])
		if base == null:
			return []
		out.append([base, false])
		var garden := texture("gardens/" + String(look.get("garden", "neat")))
		if garden != null:
			out.append([garden, false])
		var trades: Array = look.get("trades", [])
		for i in range(mini(2, trades.size())):
			var prop := texture("props/" + String(trades[i]))
			if prop != null:
				out.append([prop, i == 1])
		return out
	var tex: Texture2D = null
	if kind == "pub":
		tex = texture("places/pub_" + slug(String(place.get("name", ""))))
	if tex == null:
		tex = texture("places/" + kind)
	return [[tex, false]] if tex != null else []


static func draw_layers(ci: CanvasItem, layers: Array, rect: Rect2, tint := Color.WHITE) -> void:
	## Draws layers fitted into rect, keeping their shape, standing on the bottom edge.
	if layers.is_empty():
		return
	var t0: Texture2D = layers[0][0]
	var ts := t0.get_size()
	var k := minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var size := ts * k
	var pos := Vector2(rect.position.x + (rect.size.x - size.x) / 2.0, rect.end.y - size.y)
	for layer in layers:
		var tex: Texture2D = layer[0]
		if layer[1]:
			ci.draw_set_transform(Vector2(2.0 * pos.x + size.x, 0), 0.0, Vector2(-1, 1))
			ci.draw_texture_rect(tex, Rect2(pos, size), false, tint)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			ci.draw_texture_rect(tex, Rect2(pos, size), false, tint)
