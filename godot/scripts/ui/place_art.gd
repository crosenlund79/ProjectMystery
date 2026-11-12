## The hand-drawn look of the town: buildings, landmarks, trees and ground, drawn from simple shapes
## so every place reads at a glance - a house with a chimney, the grocery's striped awning, the
## pub's hanging sign, the clinic's cross, the workshop's barn doors, the mill's water wheel, the
## square's well, the road's signpost. Purely visual: it knows a place's kind, whether the player
## has been there, and nothing about the case.
extends RefCounted

const ART := {"home": "house", "shop": "shop", "pub": "pub", "clinic": "clinic", "workshop": "workshop",
		"mill": "mill", "square": "square", "road": "road"}


static func art_style(kind: String) -> String:
	## Which drawing a kind of place gets ("generic" for kinds this build has no drawing for).
	return String(ART.get(kind, "generic"))


static func colors(hc: bool, dusk: bool) -> Dictionary:
	if hc:
		return {"ground": Color("#000000"), "ground2": Color("#101010"), "speck": Color("#262626"),
				"road": Color("#303030"), "road_edge": Color("#ffffff"), "dash": Color("#ffd400"), "path": Color("#3c3c3c"),
				"plaza": Color("#262626"), "plaque": Color("#000000"), "plaque_dim": Color("#000000"),
				"plaque_here": Color("#3a3000"), "ink": Color("#ffffff"),
				"walls": [Color("#1c1c1c")], "roofs": [Color("#3a3a3a")], "window": Color("#ffd400"),
				"window_off": Color("#4a4a4a"), "tree": Color("#2e7d32"), "tree2": Color("#1b5e20"), "trunk": Color("#795548"),
				"water": Color("#4fc3f7"), "accent": Color("#ffd400"), "danger": Color("#ff6b5a"), "frame": Color("#ffffff"),
				"outline": Color("#ffffff"), "shade": Color(0, 0, 0, 0)}
	var c := {"ground": Color("#262c22"), "ground2": Color("#2e3528"), "speck": Color("#323a2b"),
			"road": Color("#4a4136"), "road_edge": Color("#2c2620"), "dash": Color("#6f6352"), "path": Color("#3d362c"),
			"plaza": Color("#4c473f"), "plaque": Color("#d8c8a0"), "plaque_dim": Color("#a39a82"),
			"plaque_here": Color("#ecc76a"), "ink": Color("#2a2118"),
			"walls": [Color("#cdbb95"), Color("#b9a27a"), Color("#a9a596"), Color("#c7ad86"), Color("#9f9a8a")],
			"roofs": [Color("#8a3b2c"), Color("#4f5a63"), Color("#5f4a36"), Color("#6b3f3a"), Color("#46524a")],
			"window": Color("#f2c45a"), "window_off": Color("#353840"), "tree": Color("#3c4f33"), "tree2": Color("#2f4029"),
			"trunk": Color("#4a3a2a"), "water": Color("#4f7f9a"), "accent": Color("#d9a441"), "danger": Color("#d9705f"),
			"frame": Color("#7d6230"), "outline": Color("#1a1612"), "shade": Color(0, 0, 0, 0.28)}
	if dusk:
		c["ground"] = Color("#1c2230")
		c["ground2"] = Color("#222a3a")
		c["speck"] = Color("#283043")
		c["road"] = Color("#3b3a44")
		c["path"] = Color("#2f3140")
		c["tree"] = Color("#24363a")
		c["tree2"] = Color("#1b2a30")
		c["plaza"] = Color("#3d3d48")
	return c


static func faded(c: Color, dim: bool) -> Color:
	## Places you have not been to yet are drawn greyed out, like a map you haven't walked.
	if not dim:
		return c
	var v := (c.r + c.g + c.b) / 3.0
	return Color(v, v, v, c.a).lerp(c, 0.3).darkened(0.25)


static func pick(list: Array, sd: int) -> Color:
	return list[absi(sd) % list.size()]


# --------------------------------------------------------------------------- one place
static func draw_place(ci: CanvasItem, kind: String, r: Rect2, k: Dictionary, look: Dictionary) -> void:
	## Draws a place's building or landmark inside r (the ground line is r's bottom edge).
	## look: {"lit": bool, "dim": bool, "seed": int, "hc": bool}
	var dim: bool = look.get("dim", false)
	var lit: bool = look.get("lit", false)
	var sd: int = look.get("seed", 0)
	var hc: bool = look.get("hc", false)
	var ol: Color = k["outline"]
	var olw := 2.0 if hc else 1.5
	var wall: Color = faded(pick(k["walls"], sd), dim)
	var roof: Color = faded(pick(k["roofs"], sd / 7), dim)
	var win: Color = k["window"] if lit and not dim else faded(k["window_off"], dim)
	var cx := r.position.x + r.size.x / 2.0
	var gy := r.end.y
	var h := r.size.y
	var bw := minf(r.size.x * 0.82, h * 1.3)
	match art_style(kind):
		"house":
			_house(ci, cx, gy, bw * 0.78, h, wall, roof, win, ol, olw, k)
		"shop":
			_shop(ci, cx, gy, bw, h, wall, roof, win, ol, olw, k, dim)
		"pub":
			_pub(ci, cx, gy, bw, h, wall, roof, win, ol, olw, k, dim, lit)
		"clinic":
			_clinic(ci, cx, gy, bw * 0.9, h, faded(Color("#d9d6cc") if not hc else Color("#1c1c1c"), dim), win, ol, olw, k, dim)
		"workshop":
			_workshop(ci, cx, gy, bw, h, faded(Color("#7a4b34") if not hc else Color("#1c1c1c"), dim), roof, win, ol, olw, k)
		"mill":
			_mill(ci, cx, gy, bw, h, wall, roof, win, ol, olw, k, dim)
		"square":
			_square(ci, cx, gy, bw, h, ol, olw, k, dim, lit)
		"road":
			_road(ci, cx, gy, bw, h, ol, olw, k, dim)
		_:
			_house(ci, cx, gy, bw * 0.78, h, wall, roof, win, ol, olw, k)


static func _shadow(ci: CanvasItem, cx: float, gy: float, w: float, k: Dictionary) -> void:
	var s: Color = k["shade"]
	if s.a <= 0.0:
		return
	ci.draw_rect(Rect2(cx - w / 2.0 + 3, gy - 3, w, 5), s)


static func _outline(ci: CanvasItem, pts: PackedVector2Array, ol: Color, olw: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, ol, olw, true)


static func _box(ci: CanvasItem, rect: Rect2, fill: Color, ol: Color, olw: float) -> void:
	ci.draw_rect(rect, fill)
	ci.draw_rect(rect, ol, false, olw)


static func _gable(ci: CanvasItem, left: float, right: float, base: float, peak: float, fill: Color, ol: Color,
		olw: float) -> void:
	var pts := PackedVector2Array([Vector2(left, base), Vector2((left + right) / 2.0, peak), Vector2(right, base)])
	ci.draw_colored_polygon(pts, fill)
	_outline(ci, pts, ol, olw)


static func _house(ci: CanvasItem, cx: float, gy: float, bw: float, h: float, wall: Color, roof: Color, win: Color,
		ol: Color, olw: float, k: Dictionary) -> void:
	var bh := h * 0.5
	var body := Rect2(cx - bw / 2.0, gy - bh, bw, bh)
	_shadow(ci, cx, gy, bw, k)
	_box(ci, Rect2(cx + bw * 0.16, gy - h * 0.92, bw * 0.12, h * 0.3), roof.darkened(0.2), ol, olw)
	_box(ci, body, wall, ol, olw)
	_gable(ci, body.position.x - bw * 0.1, body.end.x + bw * 0.1, body.position.y, gy - h * 0.95, roof, ol, olw)
	_box(ci, Rect2(cx - bw * 0.09, gy - bh * 0.58, bw * 0.18, bh * 0.58), wall.darkened(0.45), ol, olw * 0.7)
	var ws := bw * 0.16
	for x in [cx - bw * 0.32, cx + bw * 0.16]:
		_box(ci, Rect2(x, gy - bh * 0.78, ws, ws), win, ol, olw * 0.7)


static func _shop(ci: CanvasItem, cx: float, gy: float, bw: float, h: float, wall: Color, roof: Color, win: Color,
		ol: Color, olw: float, k: Dictionary, dim: bool) -> void:
	var bh := h * 0.62
	var body := Rect2(cx - bw / 2.0, gy - bh, bw, bh)
	_shadow(ci, cx, gy, bw, k)
	_box(ci, body, wall, ol, olw)
	_box(ci, Rect2(body.position.x - 2, body.position.y - h * 0.12, bw + 4, h * 0.12), roof, ol, olw)
	# striped awning over the shop window
	var aw_y := gy - bh * 0.62
	var stripes := 6
	var sw := bw / float(stripes)
	var red := faded(Color("#a8443a"), dim)
	var cream := faded(Color("#e6dcc4"), dim)
	for i in range(stripes):
		var x := body.position.x + i * sw
		var pts := PackedVector2Array([Vector2(x, aw_y - h * 0.1), Vector2(x + sw, aw_y - h * 0.1),
				Vector2(x + sw + 2, aw_y), Vector2(x - 2, aw_y)])
		ci.draw_colored_polygon(pts, red if i % 2 == 0 else cream)
	ci.draw_line(Vector2(body.position.x - 2, aw_y), Vector2(body.end.x + 2, aw_y), ol, olw)
	_box(ci, Rect2(body.position.x + bw * 0.08, aw_y + 3, bw * 0.5, bh * 0.45), win, ol, olw * 0.7)
	_box(ci, Rect2(cx + bw * 0.2, gy - bh * 0.55, bw * 0.2, bh * 0.55), wall.darkened(0.45), ol, olw * 0.7)


static func _pub(ci: CanvasItem, cx: float, gy: float, bw: float, h: float, wall: Color, roof: Color, win: Color,
		ol: Color, olw: float, k: Dictionary, dim: bool, lit: bool) -> void:
	var bh := h * 0.58
	var body := Rect2(cx - bw / 2.0, gy - bh, bw, bh)
	_shadow(ci, cx, gy, bw, k)
	_box(ci, Rect2(body.position.x + bw * 0.08, gy - h * 0.98, bw * 0.1, h * 0.3), roof.darkened(0.2), ol, olw)
	_box(ci, body, wall.darkened(0.12), ol, olw)
	_gable(ci, body.position.x - bw * 0.06, body.end.x + bw * 0.06, body.position.y, gy - h * 0.92, roof, ol, olw)
	# the pub always has a warm window when you are about
	var warm: Color = k["window"] if not dim else win
	for x in [body.position.x + bw * 0.1, body.position.x + bw * 0.62]:
		_box(ci, Rect2(x, gy - bh * 0.72, bw * 0.24, bh * 0.32), warm, ol, olw * 0.7)
	_box(ci, Rect2(cx - bw * 0.08, gy - bh * 0.55, bw * 0.16, bh * 0.55), wall.darkened(0.5), ol, olw * 0.7)
	# hanging sign on a bracket
	var bx := body.end.x
	var by := gy - bh * 0.95
	ci.draw_line(Vector2(bx, by), Vector2(bx + bw * 0.22, by), ol, olw)
	var sign_c := Vector2(bx + bw * 0.16, by + h * 0.13)
	ci.draw_line(Vector2(sign_c.x, by), Vector2(sign_c.x, sign_c.y - h * 0.08), ol, olw * 0.7)
	ci.draw_circle(sign_c, h * 0.09, faded(Color("#7a2e2a"), dim))
	ci.draw_arc(sign_c, h * 0.09, 0, TAU, 20, faded(k["accent"], dim), olw)
	if lit and not dim:
		var glow: Color = k["window"]
		glow.a = 0.18
		ci.draw_circle(Vector2(cx, gy - bh * 0.5), bw * 0.55, glow)


static func _clinic(ci: CanvasItem, cx: float, gy: float, bw: float, h: float, wall: Color, win: Color, ol: Color,
		olw: float, k: Dictionary, dim: bool) -> void:
	var bh := h * 0.6
	var body := Rect2(cx - bw / 2.0, gy - bh, bw, bh)
	_shadow(ci, cx, gy, bw, k)
	_box(ci, body, wall, ol, olw)
	_box(ci, Rect2(body.position.x - 3, body.position.y - h * 0.08, bw + 6, h * 0.08), wall.darkened(0.25), ol, olw)
	var red := faded(Color("#c0392b"), dim)
	var cs := h * 0.24
	var cc := Vector2(cx, body.position.y - h * 0.08 - cs * 0.7)
	ci.draw_circle(cc, cs * 0.75, wall)
	ci.draw_arc(cc, cs * 0.75, 0, TAU, 24, ol, olw)
	ci.draw_rect(Rect2(cc.x - cs * 0.16, cc.y - cs * 0.48, cs * 0.32, cs * 0.96), red)
	ci.draw_rect(Rect2(cc.x - cs * 0.48, cc.y - cs * 0.16, cs * 0.96, cs * 0.32), red)
	for x in [body.position.x + bw * 0.1, body.position.x + bw * 0.66]:
		_box(ci, Rect2(x, gy - bh * 0.75, bw * 0.22, bh * 0.3), win, ol, olw * 0.7)
	_box(ci, Rect2(cx - bw * 0.1, gy - bh * 0.5, bw * 0.2, bh * 0.5), faded(Color("#4f6f7a"), dim), ol, olw * 0.7)


static func _workshop(ci: CanvasItem, cx: float, gy: float, bw: float, h: float, wall: Color, roof: Color, win: Color,
		ol: Color, olw: float, k: Dictionary) -> void:
	var bh := h * 0.55
	var l := cx - bw / 2.0
	var rr := cx + bw / 2.0
	_shadow(ci, cx, gy, bw, k)
	# a barn: gambrel roof over plank walls
	var pts := PackedVector2Array([Vector2(l, gy), Vector2(l, gy - bh), Vector2(l + bw * 0.12, gy - h * 0.8),
			Vector2(cx, gy - h * 0.95), Vector2(rr - bw * 0.12, gy - h * 0.8), Vector2(rr, gy - bh), Vector2(rr, gy)])
	ci.draw_colored_polygon(pts, wall)
	var rpts := PackedVector2Array([Vector2(l - 3, gy - bh), Vector2(l + bw * 0.12, gy - h * 0.8), Vector2(cx, gy - h * 0.95),
			Vector2(rr - bw * 0.12, gy - h * 0.8), Vector2(rr + 3, gy - bh)])
	ci.draw_polyline(rpts, roof, maxf(3.0, h * 0.07), true)
	_outline(ci, pts, ol, olw)
	for i in range(1, 5):
		var x := l + bw * i / 5.0
		ci.draw_line(Vector2(x, gy - bh + 2), Vector2(x, gy - 1), wall.darkened(0.25), 1.0)
	var door := Rect2(cx - bw * 0.2, gy - bh * 0.8, bw * 0.4, bh * 0.8)
	_box(ci, door, wall.darkened(0.4), ol, olw)
	ci.draw_line(door.position, door.end, ol, olw * 0.8)
	ci.draw_line(Vector2(door.position.x, door.end.y), Vector2(door.end.x, door.position.y), ol, olw * 0.8)
	ci.draw_circle(Vector2(cx, gy - h * 0.72), h * 0.06, win)


static func _mill(ci: CanvasItem, cx: float, gy: float, bw: float, h: float, wall: Color, roof: Color, win: Color,
		ol: Color, olw: float, k: Dictionary, dim: bool) -> void:
	var tw := bw * 0.5
	var body := Rect2(cx - tw * 0.7, gy - h * 0.68, tw, h * 0.68)
	_shadow(ci, cx, gy, bw, k)
	# the stream that turns the wheel
	var water: Color = faded(k["water"], dim)
	var wpts := PackedVector2Array()
	for i in range(9):
		var x := cx - bw * 0.6 + bw * 1.2 * i / 8.0
		wpts.append(Vector2(x, gy - 1 + sin(i * 1.4) * 2.0))
	ci.draw_polyline(wpts, water, 3.0, true)
	_box(ci, body, wall.darkened(0.08), ol, olw)
	_gable(ci, body.position.x - 4, body.end.x + 4, body.position.y, gy - h * 0.98, roof, ol, olw)
	for y in [gy - h * 0.55, gy - h * 0.32]:
		_box(ci, Rect2(body.position.x + tw * 0.3, y, tw * 0.3, h * 0.12), win, ol, olw * 0.7)
	# the water wheel
	var wc := Vector2(body.end.x + h * 0.2, gy - h * 0.24)
	var wr := h * 0.24
	var wood := faded(Color("#6b4f33"), dim)
	ci.draw_arc(wc, wr, 0, TAU, 28, wood, maxf(2.5, h * 0.05))
	for i in range(8):
		var a := TAU * i / 8.0
		ci.draw_line(wc, wc + Vector2(cos(a), sin(a)) * wr, wood, 1.5)
	ci.draw_circle(wc, wr * 0.2, wood.darkened(0.3))
	ci.draw_arc(wc, wr, 0, TAU, 28, ol, 1.0)


static func _square(ci: CanvasItem, cx: float, gy: float, bw: float, h: float, ol: Color, olw: float, k: Dictionary,
		dim: bool, lit: bool) -> void:
	# a cobbled plaza with the town well and two lamps
	var plaza: Color = faded(k["plaza"], dim)
	var c := Vector2(cx, gy - h * 0.22)
	var pts := PackedVector2Array()
	for i in range(24):
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * bw * 0.62, sin(a) * h * 0.24))
	ci.draw_colored_polygon(pts, plaza)
	_outline(ci, pts, plaza.darkened(0.35), 1.0)
	for i in range(10):
		var a := TAU * i / 10.0 + 0.3
		ci.draw_circle(c + Vector2(cos(a) * bw * 0.4, sin(a) * h * 0.14), 1.5, plaza.lightened(0.15))
	var stone := faded(Color("#8a8478"), dim)
	var well := Vector2(cx, gy - h * 0.3)
	ci.draw_rect(Rect2(well.x - h * 0.14, well.y - h * 0.1, h * 0.28, h * 0.14), stone)
	ci.draw_rect(Rect2(well.x - h * 0.14, well.y - h * 0.1, h * 0.28, h * 0.14), ol, false, olw)
	ci.draw_line(Vector2(well.x - h * 0.12, well.y - h * 0.1), Vector2(well.x - h * 0.12, well.y - h * 0.38), ol, olw)
	ci.draw_line(Vector2(well.x + h * 0.12, well.y - h * 0.1), Vector2(well.x + h * 0.12, well.y - h * 0.38), ol, olw)
	_gable(ci, well.x - h * 0.2, well.x + h * 0.2, well.y - h * 0.38, well.y - h * 0.55, faded(k["roofs"][0], dim), ol, olw)
	var lamp_on: Color = k["window"] if lit and not dim else faded(k["window_off"], dim)
	for x in [cx - bw * 0.48, cx + bw * 0.48]:
		ci.draw_line(Vector2(x, gy - h * 0.12), Vector2(x, gy - h * 0.62), ol, olw)
		ci.draw_circle(Vector2(x, gy - h * 0.66), h * 0.06, lamp_on)


static func _road(ci: CanvasItem, cx: float, gy: float, bw: float, h: float, ol: Color, olw: float, k: Dictionary,
		dim: bool) -> void:
	# a fingerpost at the edge of town
	var wood := faded(Color("#7a5a3a"), dim)
	ci.draw_line(Vector2(cx, gy), Vector2(cx, gy - h * 0.92), ol, olw + 2)
	ci.draw_line(Vector2(cx, gy), Vector2(cx, gy - h * 0.92), wood, olw)
	var arm1 := PackedVector2Array([Vector2(cx - 2, gy - h * 0.82), Vector2(cx + bw * 0.42, gy - h * 0.82),
			Vector2(cx + bw * 0.5, gy - h * 0.74), Vector2(cx + bw * 0.42, gy - h * 0.66), Vector2(cx - 2, gy - h * 0.66)])
	var arm2 := PackedVector2Array([Vector2(cx + 2, gy - h * 0.58), Vector2(cx - bw * 0.42, gy - h * 0.58),
			Vector2(cx - bw * 0.5, gy - h * 0.5), Vector2(cx - bw * 0.42, gy - h * 0.42), Vector2(cx + 2, gy - h * 0.42)])
	for arm in [arm1, arm2]:
		ci.draw_colored_polygon(arm, wood)
		_outline(ci, arm, ol, olw * 0.8)


# --------------------------------------------------------------------------- scenery
static func draw_tree(ci: CanvasItem, p: Vector2, s: float, k: Dictionary, sd: int) -> void:
	var trunk: Color = k["trunk"]
	ci.draw_rect(Rect2(p.x - s * 0.08, p.y - s * 0.35, s * 0.16, s * 0.35), trunk)
	var a: Color = k["tree"]
	var b: Color = k["tree2"]
	if sd % 3 == 0:
		# a fir
		var pts := PackedVector2Array([Vector2(p.x - s * 0.42, p.y - s * 0.3), Vector2(p.x, p.y - s * 1.25),
				Vector2(p.x + s * 0.42, p.y - s * 0.3)])
		ci.draw_colored_polygon(pts, b)
		var pts2 := PackedVector2Array([Vector2(p.x - s * 0.32, p.y - s * 0.62), Vector2(p.x, p.y - s * 1.35),
				Vector2(p.x + s * 0.32, p.y - s * 0.62)])
		ci.draw_colored_polygon(pts2, a)
	else:
		ci.draw_circle(Vector2(p.x - s * 0.18, p.y - s * 0.55), s * 0.3, b)
		ci.draw_circle(Vector2(p.x + s * 0.18, p.y - s * 0.6), s * 0.3, b)
		ci.draw_circle(Vector2(p.x, p.y - s * 0.82), s * 0.32, a)


static func draw_pin(ci: CanvasItem, tip: Vector2, s: float, fill: Color, ol: Color) -> void:
	## A map pin whose point is at tip.
	var c := tip - Vector2(0, s * 1.1)
	var pts := PackedVector2Array([tip, c + Vector2(-s * 0.55, s * 0.25), c + Vector2(s * 0.55, s * 0.25)])
	ci.draw_colored_polygon(pts, fill)
	ci.draw_circle(c, s * 0.6, fill)
	ci.draw_arc(c, s * 0.6, 0, TAU, 20, ol, 1.5)
	ci.draw_circle(c, s * 0.22, ol)


static func draw_compass(ci: CanvasItem, c: Vector2, s: float, k: Dictionary, font: Font, fs: int) -> void:
	var fg: Color = k["frame"]
	var acc: Color = k["accent"]
	ci.draw_arc(c, s, 0, TAU, 24, fg, 1.0)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.25, 0), c + Vector2(-s * 0.25, 0)]), acc)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, s), c + Vector2(s * 0.25, 0), c + Vector2(-s * 0.25, 0)]), fg)
	ci.draw_string(font, c + Vector2(-fs * 0.3, -s - 3), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, acc)


# --------------------------------------------------------------------------- a small illustration
class View extends Control:
	## A little scene for the side panel: the place you are at, with a strip of ground and trees.
	var place := {}
	var kind := "home"
	var sd := 0
	var high_contrast := false
	var dusk := false

	func _init(kind_: String, sd_: int, hc: bool, dusk_: bool) -> void:
		kind = kind_
		sd = sd_
		high_contrast = hc
		dusk = dusk_
		name = "PlaceArt"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _ready() -> void:
		custom_minimum_size = Vector2(0, maxf(150.0, get_theme_default_font_size() * 8.0))

	func _draw() -> void:
		var Art = load("res://scripts/ui/place_art.gd")
		var k: Dictionary = Art.colors(high_contrast, dusk)
		var r := Rect2(Vector2.ZERO, size)
		var sky: Color = k["ground2"].lerp(Color("#11141b"), 0.55) if not high_contrast else Color("#000000")
		draw_rect(r, sky)
		var ground_y := size.y * 0.82
		draw_rect(Rect2(0, ground_y, size.x, size.y - ground_y), k["ground"])
		draw_line(Vector2(0, ground_y), Vector2(size.x, ground_y), k["path"], 2.0)
		var h := size.y * 0.72
		var w := minf(size.x * 0.5, h * 1.6)
		for i in range(3):
			Art.draw_tree(self, Vector2(size.x * (0.08 + 0.07 * i), ground_y + 2), h * (0.5 + 0.12 * (i % 2)), k, sd + i)
			Art.draw_tree(self, Vector2(size.x * (0.92 - 0.07 * i), ground_y + 2), h * (0.55 - 0.1 * (i % 2)), k, sd + i + 1)
		var ArtLib = load("res://scripts/core/art.gd")
		var layers: Array = ArtLib.place_layers(place) if not place.is_empty() else []
		if not layers.is_empty():
			var aw := minf(size.x * 0.7, (size.y - 6.0) * 1.43)
			ArtLib.draw_layers(self, layers, Rect2(size.x / 2.0 - aw / 2.0, 4, aw, ground_y + 4), Color.WHITE)
		else:
			Art.draw_place(self, kind, Rect2(size.x / 2.0 - w / 2.0, ground_y - h, w, h), k,
					{"lit": true, "dim": false, "seed": sd, "hc": high_contrast})
		draw_rect(r, k["frame"], false, 2.0)
