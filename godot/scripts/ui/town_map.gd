## The compressed town: every place in the case as a building on a small street plan.
## Buildings and the people you have seen are real Buttons (focusable, with tooltips); the streets,
## lanes and markers are drawn. The layout is computed from the places' kinds, so any case's town
## fits: homes along two lanes, trades along the high street, the square, the road and the mill
## on the main road through town.
extends Control

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")

signal place_chosen(pid: String)
signal person_chosen(rid: String)

const KIND_NAMES := {"square": "Town square", "road": "Road", "shop": "Shop", "pub": "Public house",
		"workshop": "Workshop", "clinic": "Clinic", "mill": "Mill", "home": "Home"}

var town
var engine
var high_contrast := false
var _tiles := {}
var _tokens := {}
var _rows := []
var _band_y := 0.0


func setup(town_, engine_, high_contrast_: bool) -> void:
	town = town_
	engine = engine_
	high_contrast = high_contrast_
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


func _add_tile(p: Dictionary) -> void:
	var pid: String = p["id"]
	var b := Button.new()
	b.name = "Tile_" + pid.replace(":", "_")
	b.text = "%s\n%s" % [short_name(p), KIND_NAMES.get(p["kind"], String(p["kind"]).capitalize())]
	b.focus_mode = Control.FOCUS_ALL
	var here: bool = town.at() == pid
	if here:
		b.theme_type_variation = "MapTileHere"
	elif pid == town.scene():
		b.theme_type_variation = "MapTileScene"
	elif town.visited(pid):
		b.theme_type_variation = "MapTile"
	else:
		b.theme_type_variation = "MapTileUnvisited"
	b.tooltip_text = _tile_tip(p)
	b.pressed.connect(_choose_place.bind(pid))
	add_child(b)
	_tiles[pid] = b


func _tile_tip(p: Dictionary) -> String:
	var pid: String = p["id"]
	var full := String(p["name"])
	var lines := PackedStringArray([full.substr(0, 1).to_upper() + full.substr(1)])
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
		t.tooltip_text = "%s, %s\nSeen at %s. Click to go and talk to them." % [r["name"], r["occupation"],
				engine.place_name(p["id"])]
		t.focus_mode = Control.FOCUS_ALL
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


func _arrange() -> void:
	## Rows of buildings spread across the width; the main road runs through the middle row.
	if _rows.is_empty() or size.x < 10:
		return
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
	var gap := maxf(8.0, (size.y - total) / float(_rows.size() + 1))
	var y := gap
	for i in range(_rows.size()):
		var row: Array = _rows[i]
		var widths := []
		var sum := 0.0
		for p in row:
			var w: float = _tiles[p["id"]].get_combined_minimum_size().x
			widths.append(w)
			sum += w
		var spare := maxf(0.0, size.x - sum)
		var step := spare / float(row.size() + 1)
		var x := step
		for j in range(row.size()):
			var tile: Button = _tiles[row[j]["id"]]
			tile.size = Vector2(widths[j], row_h[i])
			tile.position = Vector2(x, y)
			_place_tokens(row[j]["id"], tile.position + Vector2(widths[j] / 2.0, row_h[i] + 4))
			x += widths[j] + step
		if row[0]["kind"] in ["square", "road", "mill"]:
			_band_y = y + row_h[i] / 2.0
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
	var x := top_center.x - w / 2.0
	for t in mine:
		var s: Vector2 = t.get_combined_minimum_size()
		t.size = s
		t.position = Vector2(x, top_center.y)
		x += s.x + 4


func _draw() -> void:
	var p := ThemeBuilder.palette(high_contrast)
	draw_rect(Rect2(Vector2.ZERO, size), p["paper"].darkened(0.55))
	# faint town blocks
	var block: Color = p["line"]
	block.a = 0.25
	var step := 48.0
	var gx := 0.0
	while gx < size.x:
		draw_line(Vector2(gx, 0), Vector2(gx, size.y), block, 1.0)
		gx += step
	var gy := 0.0
	while gy < size.y:
		draw_line(Vector2(0, gy), Vector2(size.x, gy), block, 1.0)
		gy += step
	if _tiles.is_empty():
		return
	# the main road through town, and lanes from each building to it
	var road: Color = p["card_hi"]
	var band := _band_y if _band_y > 0 else size.y / 2.0
	draw_rect(Rect2(0, band - 14, size.x, 28), road)
	var kerb: Color = p["accent_dim"]
	kerb.a = 0.6
	draw_line(Vector2(0, band - 14), Vector2(size.x, band - 14), kerb, 1.0)
	draw_line(Vector2(0, band + 14), Vector2(size.x, band + 14), kerb, 1.0)
	var lane: Color = p["line"]
	for pid in _tiles:
		var t: Button = _tiles[pid]
		var c := t.position + t.size / 2.0
		if absf(c.y - band) > t.size.y:
			var from_y := t.position.y + (t.size.y if c.y < band else 0.0)
			draw_line(Vector2(c.x, from_y), Vector2(c.x, band - 14 if c.y < band else band + 14), lane, 3.0)
	# the scene of the incident, and you
	var scene_tile = _tiles.get(town.scene())
	if scene_tile != null:
		var r: Rect2 = scene_tile.get_rect().grow(6)
		draw_rect(r, p["danger"], false, 2.0)
	var here = _tiles.get(town.at())
	if here != null:
		var r2: Rect2 = here.get_rect().grow(10)
		draw_rect(r2, p["accent"], false, 3.0)
		var font := get_theme_default_font()
		var fs := maxi(12, int(get_theme_default_font_size() * 0.8))
		draw_string(font, Vector2(r2.position.x, r2.position.y - 4), "You are here", HORIZONTAL_ALIGNMENT_LEFT, -1,
				fs, p["accent"])
