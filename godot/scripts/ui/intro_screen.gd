## The opening: a handful of still frames of a night in town, each faded in with a line of text.
## Click or press Enter for the next frame, Escape (or Skip) to go straight to the menu.
## Frames and lines are replaceable artwork: res://art/intro/template_frame_<n>.png and template_captions.txt
## (see res://art/README.md). Up to eight frames are shown, as many as there are.
extends Control

const ArtLib = preload("res://scripts/core/art.gd")
const Kit = preload("res://scripts/ui/kit.gd")

signal finished

const FADE := 0.7
const HOLD := 3.4

var frames: Array = []
var captions := PackedStringArray()
var index := -1
var image: TextureRect
var caption: Label
var tween: Tween
var _done := false


func _init() -> void:
	name = "IntroScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	image = TextureRect.new()
	image.name = "IntroFrame"
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	caption = Kit.label("", "HeadingLabel")
	caption.name = "IntroCaption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -110
	caption.offset_bottom = -50
	caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	var skip := Kit.button("Skip  (Esc)", "Skip the opening and go to the menu", "", "SkipIntro")
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.position = Vector2(-150, -56)
	skip.pressed.connect(finish)
	add_child(skip)
	for i in range(1, 9):
		var t := ArtLib.texture("intro/frame_%d" % i)
		if t == null:
			break
		frames.append(t)
	captions = ArtLib.lines("intro/captions")
	if frames.is_empty():
		finish.call_deferred()
		return
	next()


func next() -> void:
	if _done:
		return
	index += 1
	if index >= frames.size():
		finish()
		return
	image.texture = frames[index]
	caption.text = captions[index] if index < captions.size() else ""
	image.modulate.a = 0.0
	caption.modulate.a = 0.0
	if tween != null:
		tween.kill()
	tween = create_tween()
	tween.tween_property(image, "modulate:a", 1.0, FADE)
	tween.parallel().tween_property(caption, "modulate:a", 1.0, FADE)
	tween.tween_interval(HOLD)
	tween.tween_property(image, "modulate:a", 0.0, FADE)
	tween.parallel().tween_property(caption, "modulate:a", 0.0, FADE)
	tween.tween_callback(next)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		next()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		finish()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		next()
		get_viewport().set_input_as_handled()


func finish() -> void:
	if _done:
		return
	_done = true
	if tween != null:
		tween.kill()
	finished.emit()
