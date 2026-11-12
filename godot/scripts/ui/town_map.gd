## The town, drawn as a small hand-made map: every place in the case is a building you can see -
## houses along two lanes, the trades along the high street, the square, the road and the mill on
## the main road through town - set in a clearing in the woods, with the town's name on the frame.
## Buildings and the people you have seen are real Buttons (focusable, with tooltips and the same
## names as before); the buttons are transparent and sit over the drawn building and its name
## sign, so clicking a building works exactly as it did. All drawing is in place_art.gd.
extends Control

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const Art = preload("res://scripts/ui/place_art.gd")
const ArtLib = preload("res://scripts/core/art.gd")

signal place_chosen(pid: String)
signal person_chosen(rid: String)

const KIND_NAMES := {"square": "Town square", "road": "Road", "shop": "Shop", "pub": "Public house",
		"workshop": "Workshop", "clinic": "Clinic", "mill": "Mill", "home": "Home"}

var town
var engine
var high_contrast := false
var dusk := false
var _tiles := {}
var _tokens := {}
var _rows := []
var _band_y := 0.0
var _title_h := 0.0
var _legend_h := 0.0


func setup(town_, engine_, high_contrast_: bool) -> void:
	town = town_
	engine = engine_
	high_contrast = high_contrast_
	var hour := int(engine.data.get("start_time", 540)) % 1440 / 60
	dusk = hour >= 18 or hour < 7
	name = "TownMap"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()


static func short_name(p: Dictionary) -> String:
	var n := String(p["name"])
	if n.begins_with("the "):
		n = n.substr(4)
	return n.substr(0, 1).to_upper() + n.substr(1)


func rebuild() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_tiles.clear()
	_tokens.clear()
	var homes := []
	var trades := []
	var band := []
	for p in town.places():
		match String(p["kind"]):
			"home":
				homes.append(p)
			"square", "road", "mill":
				band.append(p)
			_:
				trades.append(p)
	band.sort_custom(_band_order)
	var half := int(ceil(homes.size() / 2.0))
	var north := homes.slice(0, half)
	var south := homes.slice(half)
	var trades_n := trades
	var trades_s := []
	if trades.size() > 5:
		trades_n = trades.slice(0, int(ceil(trades.size() / 2.0)))
		trades_s = trades.slice(int(ceil(trades.size() / 2.0)))
	_rows = []
	for row in [north, trades_n, band, trades_s, south]:
		if not row.is_empty():
			_rows.append(row)
	for row in _rows:
		for p in row:
			_add_tile(p)
			_add_tokens(p)
	call_deferred("_arrange")


func _band_order(a, b) -> bool:
	var order := {"square": 0, "road": 1, "mill": 2}
	return order.get(a["kind"], 3) < order.get(b["kind"], 3)


func tile_state(pid: String) -> String:
	## How a building is marked on the map: here, scene, visited or unvisited.
	if town.at() == pid:
		return "here"
	if pid == town.scene():
		return "scene"
	return "visited" if town.visited(pid) else "unvisited"


func _add_tile(p: Dictionary) -> void:
	var pid: String = p["id"]
	var b := Button.new()
	b.name = "Tile_" + pid.replace(":", "_")
	b.text = short_name(p)
	b.focus_mode = Control.FOCUS_ALL
	b.theme_type_variation = {"here": "MapTileHere", "scene": "MapTileScene", "visited": "MapTile",
			"unvisited": "MapTileUnvisited"}[tile_state(pid)]
	b.tooltip_text = _tile_tip(p)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(_choose_place.bind(pid))
	add_child(b)
	_tiles[pid] = b


func _tile_tip(p: Dictionary) -> String:
	var pid: String = p["id"]
	var full := String(p["name"])
	var lines := PackedStringArray([full.substr(0, 1).to_upper() + full.substr(1) + "  ·  "
			+ String(KIND_NAMES.get(p["kind"], String(p["kind"]).capitalize()))])
	if town.at() == pid:
		lines.append("You are here.")
	if pid == town.scene():
		lines.append("Where it happened: %s" % engine.data["hook"]["title"])
	if not p["owners"].is_empty():
		var owners := PackedStringArray()
		for o in p["owners"]:
			owners.append(engine.resident(o).get("name", o))
		lines.append("Belongs to " + ", ".join(owners))
	var books: Array = town.records_at(pid)
	for k in books:
		lines.append("Kept here: " + String(engine.data["records"][k]["title"]))
	for vid in town.vehicles_at(pid):
		lines.append("Parked here: " + String(engine.vehicle(vid)["name"]))
	var seen: Array = town.known_people_at(pid)
	if not seen.is_empty():
		var names := PackedStringArray()
		for rid in seen:
			names.append(engine.resident(rid)["first"])
		lines.append("You saw here: " + ", ".join(names))
	elif not town.visited(pid):
		lines.append("You haven't been here yet.")
	lines.append("Click to go there.")
	return "\n".join(lines)


func _add_tokens(p: Dictionary) -> void:
	for rid in town.known_people_at(p["id"]):
		var r: Dictionary = engine.resident(rid)
		var t := Button.new()
		t.name = "Person_" + String(rid)
		var parts := String(r["name"]).split(" ")
		t.text = (parts[0].left(1) + (parts[parts.size() - 1].left(1) if parts.size() > 1 else "")).to_upper()
		t.theme_type_variation = "PersonToken"
		var face: Array = ArtLib.portrait(r, "neutral")
		if face[0] != null:
			t.icon = face[0]
			t.expand_icon = true
			t.text = ""
			t.custom_minimum_size = Vector2(34, 34)
		t.tooltip_text = "%s, %s\nSeen at %s. Click to go and talk to them." % [r["name"], r["occupation"],
				engine.place_name(p["id"])]
		t.focus_mode = Control.FOCUS_ALL
		t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		t.pressed.connect(_choose_person.bind(rid))
		add_child(t)
		_tokens[rid] = [t, p["id"]]


func _choose_place(pid: String) -> void:
	place_chosen.emit(pid)


func _choose_person(rid: String) -> void:
	person_chosen.emit(rid)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		if not _rows.is_empty():
			_arrange()


func _art_h() -> float:
	return float(get_theme_constant("art_height", "MapTile"))


static func _jitter(key: String, amount: float) -> Vector2:
	## A small, stable offset per building so the town does not sit on a ruler-straight grid.
	var hh := absi(hash(key))
	return Vector2(float(hh % 17 - 8) / 8.0, float((hh / 17) % 13 - 6) / 6.0) * amount


func _arrange() -> void:
	## Rows of buildings spread across the width; the main road runs through the middle row.
	## A band at the top holds the town's name, and a strip at the bottom the map key.
	if _rows.is_empty() or size.x < 10:
		return
	var fs := get_theme_default_font_size()
	_title_h = fs * 2.0
	_legend_h = fs * 1.4
	var art_w := _art_h() * 1.45
	var token_h := 0.0
	for k in _tokens:
		token_h = maxf(token_h, _tokens[k][0].get_combined_minimum_size().y)
	var row_h := []
	var total := 0.0
	for row in _rows:
		var h := 0.0
		for p in row:
			h = maxf(h, _tiles[p["id"]].get_combined_minimum_size().y)
		row_h.append(h)
		total += h + token_h + 6
	var usable := size.y - _title_h - _legend_h
	var gap := maxf(6.0, (usable - total) / float(_rows.size() + 1))
	var y := _title_h + gap
	for i in range(_rows.size()):
		var row: Array = _rows[i]
		var widths := []
		var sum := 0.0
		for p in row:
			var w: float = maxf(_tiles[p["id"]].get_combined_minimum_size().x, art_w)
			widths.append(w)
			sum += w
		var spare := maxf(0.0, size.x - sum)
		var step := spare / float(row.size() + 1)
		var x := step
		for j in range(row.size()):
			var pid: String = row[j]["id"]
			var tile: Button = _tiles[pid]
			var jit := _jitter(pid, 1.0) * Vector2(minf(10.0, step / 3.0), minf(6.0, gap / 3.0))
			tile.size = Vector2(widths[j], row_h[i])
			tile.position = Vector2(x, y) + jit
			_place_tokens(pid, tile.position + Vector2(widths[j] / 2.0, row_h[i] + 4))
			x += widths[j] + step
		if row[0]["kind"] in ["square", "road", "mill"]:
			_band_y = y + row_h[i] - 4
		y += row_h[i] + token_h + 6 + gap
	queue_redraw()


func _place_tokens(pid: String, top_center: Vector2) -> void:
	var mine := []
	for rid in _tokens:
		if _tokens[rid][1] == pid:
			mine.append(_tokens[rid][0])
	if mine.is_empty():
		return
	var w := 0.0
	for t in mine:
		w += t.get_combined_minimum_size().x + 4
	var x := clampf(top_center.x - w / 2.0, 2.0, maxf(2.0, size.x - w - 2.0))
	for t in mine:
		var s: Vector2 = t.get_combined_minimum_size()
		t.size = s
		t.position = Vector2(x, top_center.y)
		x += s.x + 4


# =========================================================================== drawing
func _draw() -> void:
	var k: Dictionary = Art.colors(high_contrast, dusk)
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, k["ground"])
	if _tiles.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(engine.data.get("town", "")))
	_ground_texture(rng, k)
	var band := _band_y if _band_y > 0 else size.y / 2.0
	_lanes(k, band)
	_main_road(k, band)
	_trees(rng, k, band)
	var art_h := _art_h()
	var here = _tiles.get(town.at())
	if here != null:
		var glow: Color = k["accent"]
		for i in range(4):
			glow.a = 0.07 + 0.03 * i
			draw_circle(here.position + Vector2(here.size.x / 2.0, art_h * 0.6), art_h * (0.95 - 0.15 * i), glow)
	for pid in _tiles:
		_building(pid, k, art_h)
	_markers(k, art_h)
	_frame(k)


func _ground_texture(rng: RandomNumberGenerator, k: Dictionary) -> void:
	var a: Color = k["ground2"]
	var b: Color = k["speck"]
	for i in range(int(size.x * size.y / 900.0)):
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		if i % 4 == 0:
			draw_circle(p, rng.randf_range(6.0, 18.0), Color(a.r, a.g, a.b, 0.35))
		else:
			draw_circle(p, rng.randf_range(0.8, 1.8), b)


func _lanes(k: Dictionary, band: float) -> void:
	## Dirt lanes from each building down (or up) to the main road, gently curved.
	var path: Color = k["path"]
	var art_h := _art_h()
	for pid in _tiles:
		var t: Button = _tiles[pid]
		var foot := Vector2(t.position.x + t.size.x / 2.0, t.position.y + art_h)
		if absf(foot.y - band) < art_h * 0.6:
			continue
		var to := Vector2(foot.x + _jitter(pid, 18.0).x, band + (-10.0 if foot.y < band else 10.0))
		var ctrl := Vector2((foot.x + to.x) / 2.0 + _jitter(pid + "c", 26.0).x, (foot.y + to.y) / 2.0)
		var pts := PackedVector2Array()
		for i in range(13):
			var tt := i / 12.0
			pts.append(foot.lerp(ctrl, tt).lerp(ctrl.lerp(to, tt), tt))
		draw_polyline(pts, path.darkened(0.2), 7.0, true)
		draw_polyline(pts, path, 5.0, true)


func _main_road(k: Dictionary, band: float) -> void:
	var pts := PackedVector2Array()
	var n := 24
	for i in range(n + 1):
		var x := -20.0 + (size.x + 40.0) * i / float(n)
		pts.append(Vector2(x, band + sin(x / maxf(1.0, size.x) * TAU * 0.9 + 0.6) * 5.0))
	draw_polyline(pts, k["road_edge"], 30.0, true)
	draw_polyline(pts, k["road"], 25.0, true)
	var dash: Color = k["dash"]
	for i in range(0, n, 2):
		draw_line(pts[i].lerp(pts[i + 1], 0.25), pts[i].lerp(pts[i + 1], 0.75), dash, 2.0, true)


func _blocked(p: Vector2, pad: float, band: float) -> bool:
	if p.y < _title_h + 4 or p.y > size.y - _legend_h - 2 or absf(p.y - band) < 26 + pad:
		return true
	for pid in _tiles:
		if _tiles[pid].get_rect().grow(pad).has_point(p):
			return true
	for rid in _tokens:
		if _tokens[rid][0].get_rect().grow(pad).has_point(p):
			return true
	return false


func _trees(rng: RandomNumberGenerator, k: Dictionary, band: float) -> void:
	## Woods round the edges of town, thinning towards the middle: an isolated place.
	var s := maxf(14.0, _art_h() * 0.42)
	var step := s * 1.15
	var y := _title_h + s * 1.3
	while y < size.y - _legend_h:
		var x := s * 0.4
		while x < size.x:
			var p := Vector2(x + rng.randf_range(-step * 0.35, step * 0.35), y + rng.randf_range(-step * 0.3, step * 0.3))
			var edge := minf(minf(p.x, size.x - p.x), minf(p.y - _title_h, size.y - _legend_h - p.y))
			var chance := 0.85 if edge < s * 2.2 else 0.16
			if rng.randf() < chance and not _blocked(p, s * 0.55, band):
				Art.draw_tree(self, p, s * rng.randf_range(0.8, 1.15), k, rng.randi())
			x += step
		y += step * 0.9


func _building(pid: String, k: Dictionary, art_h: float) -> void:
	var t: Button = _tiles[pid]
	var p: Dictionary = town.place(pid)
	var state := tile_state(pid)
	var dim := state == "unvisited"
	var art := Rect2(t.position.x + 4, t.position.y + 2, t.size.x - 8, art_h - 4)
	var layers: Array = ArtLib.place_layers(p)
	if not layers.is_empty():
		# the place's own picture (res://art, replaceable); greyed until visited, a touch darker at dusk
		var tint := Color.WHITE
		if dim:
			tint = Color(0.5, 0.52, 0.58)
		elif dusk and state != "here":
			tint = Color(0.82, 0.84, 0.98)
		# the pictures leave a margin round the building: draw them half as big again, standing on the sign
		var w := art.size.x * 1.5
		var h := w * 0.7
		ArtLib.draw_layers(self, layers, Rect2(art.position.x + art.size.x / 2.0 - w / 2.0, art.end.y + h * 0.1 - h, w, h), tint)
	else:
		Art.draw_place(self, String(p["kind"]), art, k,
				{"lit": state == "here" or (dusk and not dim), "dim": dim, "seed": hash(pid), "hc": high_contrast})
	# the name sign under the building
	var plate := Rect2(t.position.x + 3, t.position.y + art_h - 1, t.size.x - 6, t.size.y - art_h - 1)
	var face: Color = k["plaque"]
	if state == "here":
		face = k["plaque_here"]
	elif dim:
		face = k["plaque_dim"]
	draw_rect(Rect2(plate.position + Vector2(2, 2), plate.size), Color(0, 0, 0, 0.35))
	draw_rect(plate, face)
	var edge: Color = k["danger"] if state == "scene" else (k["accent"] if state == "here" else k["outline"])
	draw_rect(plate, edge, false, 2.0 if state in ["scene", "here"] else 1.0)


func _markers(k: Dictionary, art_h: float) -> void:
	## The scene ringed in red with a warning badge; you, with a pin.
	var font := get_theme_font("font", "MapTile")
	var scene_tile = _tiles.get(town.scene())
	if scene_tile != null:
		var c: Vector2 = scene_tile.position + Vector2(scene_tile.size.x / 2.0, art_h * 0.55)
		var rx: float = scene_tile.size.x * 0.56
		var ry := art_h * 0.56
		var ring := PackedVector2Array()
		for i in range(37):
			var a := TAU * i / 36.0
			ring.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		for i in range(0, 36, 2):
			draw_line(ring[i], ring[i + 1], k["danger"], 2.5, true)
		var badge := Vector2(scene_tile.position.x + 10, scene_tile.position.y + 10)
		draw_circle(badge, 9, k["danger"])
		draw_arc(badge, 9, 0, TAU, 20, k["outline"], 1.0)
		draw_string(font, badge + Vector2(-3, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	var here = _tiles.get(town.at())
	if here != null:
		var tip := Vector2(here.position.x + here.size.x - 12, here.position.y + art_h * 0.35)
		Art.draw_pin(self, tip, maxf(9.0, art_h * 0.17), k["accent"], k["outline"])


func _frame(k: Dictionary) -> void:
	## Vignette, a double frame, the town's name on a cartouche, a compass and the map key.
	for i in range(7):
		draw_rect(Rect2(Vector2.ONE * i * 4, size - Vector2.ONE * i * 8), Color(0, 0, 0, 0.16 - 0.02 * i), false, 4.0)
	var fr: Color = k["frame"]
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), fr, false, 2.0)
	draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), fr.darkened(0.2), false, 1.0)
	var font := get_theme_font("font", "MapTile")
	var fs := get_theme_default_font_size()
	var title := String(engine.data.get("town", "")).to_upper()
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var cy := _title_h / 2.0 + 2
	var half := tw / 2.0 + fs
	var cx := size.x / 2.0
	var ribbon := PackedVector2Array([Vector2(cx - half - fs * 0.6, cy - fs * 0.75), Vector2(cx + half + fs * 0.6, cy - fs * 0.75),
			Vector2(cx + half, cy), Vector2(cx + half + fs * 0.6, cy + fs * 0.75), Vector2(cx - half - fs * 0.6, cy + fs * 0.75),
			Vector2(cx - half, cy)])
	draw_colored_polygon(ribbon, k["plaque"])
	var closed := ribbon.duplicate()
	closed.append(ribbon[0])
	draw_polyline(closed, fr, 1.5, true)
	draw_string(font, Vector2(cx - tw / 2.0, cy + fs * 0.35), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, k["ink"])
	if size.x - (cx + half + fs) > fs * 3:
		Art.draw_compass(self, Vector2(size.x - fs * 1.6, cy + 2), fs * 0.75, k, font, maxi(11, int(fs * 0.6)))
	# the key
	var small := maxi(11, int(fs * 0.7))
	var ly := size.y - _legend_h / 2.0 + small * 0.35
	var lx := 16.0
	Art.draw_pin(self, Vector2(lx + 4, ly + 2), small * 0.55, k["accent"], k["outline"])
	draw_string(font, Vector2(lx + 14, ly), "You are here", HORIZONTAL_ALIGNMENT_LEFT, -1, small, k["accent"])
	lx += 18 + font.get_string_size("You are here", HORIZONTAL_ALIGNMENT_LEFT, -1, small).x + 18
	draw_arc(Vector2(lx + 6, ly - small * 0.3), small * 0.5, 0, TAU, 16, k["danger"], 2.0)
	draw_string(font, Vector2(lx + 16, ly), "Where it happened", HORIZONTAL_ALIGNMENT_LEFT, -1, small, k["danger"])
	lx += 22 + font.get_string_size("Where it happened", HORIZONTAL_ALIGNMENT_LEFT, -1, small).x + 18
	if lx + small * 8 < size.x:
		var dimc: Color = k["plaque_dim"]
		draw_rect(Rect2(lx, ly - small * 0.8, small, small * 0.9), dimc)
		draw_rect(Rect2(lx, ly - small * 0.8, small, small * 0.9), k["frame"], false, 1.0)
		draw_string(font, Vector2(lx + small + 6, ly), "Not visited yet", HORIZONTAL_ALIGNMENT_LEFT, -1, small,
				k["frame"] if high_contrast else dimc)
