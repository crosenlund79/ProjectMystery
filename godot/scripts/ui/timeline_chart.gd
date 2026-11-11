## An interactive chart of the claims the player has collected: one lane per person, stays as
## bars, sightings as dots. Claims that conflict are outlined in red. Click a mark to select its
## notebook entry; hover for details. Draws only what the player has discovered.
extends Control

signal entry_selected(entry_id: String)

const Clock = preload("res://scripts/core/clock.gd")
const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")

const LANE_H := 34
const LEFT := 150
const TOP := 28

var facts: Array = []
var lanes: Array = []
var lane_names := {}
var conflicted := {}
var t0 := 0
var t1 := 1
var selected := ""
var engine
var high_contrast := false
var _hits: Array = []


func setup(timeline: Dictionary, engine_, only_person := "", selected_entry := "") -> void:
	engine = engine_
	selected = selected_entry
	for c in timeline["conflicts"]:
		conflicted[c[0]] = true
		conflicted[c[1]] = true
	for f in timeline["facts"]:
		if only_person == "" or f["who"] == only_person:
			facts.append(f)
	var seen := {}
	for f in facts:
		if not seen.has(f["who"]):
			seen[f["who"]] = true
			lanes.append(f["who"])
			lane_names[f["who"]] = engine.first_name(f["who"])
	lanes.sort_custom(_lane_less)
	if not facts.is_empty():
		t0 = int(facts[0]["from"])
		t1 = int(facts[0]["to"])
		for f in facts:
			t0 = mini(t0, int(f["from"]))
			t1 = maxi(t1, int(f["to"]))
		t0 -= 30
		t1 += 30
	custom_minimum_size = Vector2(600, TOP + 12 + LANE_H * maxi(1, lanes.size()))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_text = " "
	mouse_filter = Control.MOUSE_FILTER_STOP


func _lane_less(a, b) -> bool:
	return String(lane_names[a]) < String(lane_names[b])


func _x(t: int) -> float:
	var w := maxf(1.0, size.x - LEFT - 16)
	return LEFT + w * float(t - t0) / float(maxi(1, t1 - t0))


func _draw() -> void:
	var p := ThemeBuilder.palette(high_contrast)
	var font := get_theme_default_font()
	var fs := get_theme_default_font_size()
	draw_rect(Rect2(Vector2.ZERO, size), p["card"])
	_hits.clear()
	if facts.is_empty():
		draw_string(font, Vector2(16, TOP + 10), "Nothing to plot yet: collect statements about where people were.",
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, p["muted"])
		return
	# hour ticks
	var first_hour := int(ceil(float(t0) / 60.0)) * 60
	var step := 60
	while (t1 - t0) / step > 14:
		step *= 2
	var t := first_hour
	while t <= t1:
		var x := _x(t)
		draw_line(Vector2(x, TOP - 6), Vector2(x, size.y), p["line"], 1.0)
		var label := Clock.clock(t) if t % 1440 != 0 else "Day %d" % Clock.day_of(t)
		draw_string(font, Vector2(x + 3, TOP - 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.75), p["muted"])
		t += step
	for i in range(lanes.size()):
		var who: String = lanes[i]
		var y := TOP + i * LANE_H
		draw_string(font, Vector2(8, y + LANE_H * 0.65), lane_names[who], HORIZONTAL_ALIGNMENT_LEFT, LEFT - 16, fs, p["text"])
		draw_line(Vector2(LEFT, y + LANE_H / 2.0), Vector2(size.x - 16, y + LANE_H / 2.0), p["line"], 1.0)
		for f in facts:
			if f["who"] != who:
				continue
			var bad: bool = conflicted.has(f["entry"])
			var col: Color = p["danger"] if bad else p["accent"]
			if f.get("hedged", false):
				col = col.darkened(0.35)
			var x0 := _x(int(f["from"]))
			var x1 := _x(int(f["to"]))
			var rect: Rect2
			if int(f["from"]) == int(f["to"]):
				rect = Rect2(x0 - 6, y + LANE_H / 2.0 - 6, 12, 12)
				draw_circle(rect.get_center(), 6, col)
			else:
				rect = Rect2(x0, y + 8, maxf(4.0, x1 - x0), LANE_H - 16)
				draw_rect(rect, col.darkened(0.25))
			if bad:
				draw_rect(rect.grow(2), p["danger"], false, 2.0)
			if f["entry"] == selected:
				draw_rect(rect.grow(4), p["text"], false, 2.0)
			_hits.append([rect.grow(4), f])


func _fact_at(pos: Vector2) -> Dictionary:
	for h in _hits:
		if h[0].has_point(pos):
			return h[1]
	return {}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var f: Dictionary = _fact_at(event.position)
		if not f.is_empty():
			entry_selected.emit(String(f["entry"]))
			accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	var f: Dictionary = _fact_at(at_position)
	if f.is_empty():
		return ""
	var when := Clock.around(f["from"]) if int(f["from"]) == int(f["to"]) else \
			"%s to %s" % [Clock.fmt(f["from"]), Clock.fmt(f["to"])]
	var text := "[%s] %s at %s, %s" % [f["entry"], lane_names.get(f["who"], f["who"]), engine.place_name(f["place"]), when]
	if conflicted.has(f["entry"]):
		text += "\nConflicts with another account."
	if f.get("hedged", false):
		text += "\nThe witness was not sure who it was."
	return text
