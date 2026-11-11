## Small helpers for building screens out of native Control nodes.
extends RefCounted


static func label(text: String, variation := "", wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func button(text: String, tooltip := "", variation := "", node_name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_ALL
	if variation != "":
		b.theme_type_variation = variation
	if node_name != "":
		b.name = node_name
	return b


static func panel(variation := "Card") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


static func vbox(separation := -1) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if separation >= 0:
		v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation := -1) -> HBoxContainer:
	var h := HBoxContainer.new()
	if separation >= 0:
		h.add_theme_constant_override("separation", separation)
	return h


static func flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f


static func scroll(child: Control, expand_vertical := true) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_vertical:
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func margin(child: Control, m := 24) -> MarginContainer:
	var c := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		c.add_theme_constant_override(side, m)
	c.add_child(child)
	return c


static func spacer(height := 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


static func grow() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func option(items: Array, selected := 0, tooltip := "") -> OptionButton:
	## items: [[label, id], ...]
	var o := OptionButton.new()
	for it in items:
		o.add_item(it[0], it[1])
	if items.size() > 0:
		o.select(clampi(selected, 0, items.size() - 1))
	o.tooltip_text = tooltip
	return o


static func tag_text(ids: Array) -> String:
	## The notebook ids a line was filed under: "S4", "S4, S7", "S4-S9".
	if ids.is_empty():
		return ""
	if ids.size() <= 2:
		return ", ".join(PackedStringArray(ids))
	var start := String(ids[0]).substr(1).to_int()
	var run := true
	for i in range(ids.size()):
		if String(ids[i]).substr(1).to_int() != start + i:
			run = false
	if run:
		return "%s-%s" % [ids[0], ids[ids.size() - 1]]
	return ", ".join(PackedStringArray(ids))
