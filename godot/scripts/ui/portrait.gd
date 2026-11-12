## A resident's portrait: their face (with an expression) and their work clothes, in a small frame.
## Falls back to initials when there is no art at all.
extends Control

const ArtLib = preload("res://scripts/core/art.gd")

var resident: Dictionary = {}
var expression := "neutral"
var side := 96.0
var frame_color := Color("#363c4a")
var back_color := Color("#2a303c")


func setup(r: Dictionary, px := 96.0, expr := "neutral") -> Control:
	resident = r
	side = px
	expression = expr
	name = "Portrait_" + String(r.get("id", ""))
	custom_minimum_size = Vector2(px, px)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "%s, %s" % [r.get("name", ""), r.get("occupation", "")]
	return self


func set_expression(e: String) -> void:
	if e != expression:
		expression = e
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(side, side))
	var dead := String(resident.get("condition", "")) == "deceased"
	draw_rect(rect, back_color)
	draw_circle(Vector2(side / 2.0, side * 0.52), side * 0.42, back_color.lightened(0.08))
	var layers: Array = ArtLib.portrait(resident, expression)
	var tint := Color(0.62, 0.62, 0.66) if dead else Color.WHITE
	if layers[0] != null:
		draw_texture_rect(layers[0], rect, false, tint)
		if layers[1] != null:
			draw_texture_rect(layers[1], rect, false, tint)
	else:
		var parts := String(resident.get("name", "?")).split(" ")
		var ini := (parts[0].left(1) + (parts[parts.size() - 1].left(1) if parts.size() > 1 else "")).to_upper()
		var font := get_theme_default_font()
		var fs := int(side * 0.36)
		draw_string(font, Vector2(0, side / 2.0 + fs * 0.35), ini, HORIZONTAL_ALIGNMENT_CENTER, side, fs, Color("#e8e2d4"))
	draw_rect(rect, frame_color, false, 2.0)
