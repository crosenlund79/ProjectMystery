## The dark detective look, built in code from native Control themes. Text size and high
## contrast are settings; changing them rebuilds this Theme and every screen restyles itself.
extends RefCounted

const SIZES := [16, 18, 21, 25]
const SIZE_NAMES := ["Small", "Medium", "Large", "Extra large"]


static func palette(high_contrast: bool) -> Dictionary:
	if high_contrast:
		return {"bg": Color("#000000"), "panel": Color("#050505"), "card": Color("#101010"), "card_hi": Color("#1c1c1c"),
				"line": Color("#ffffff"), "text": Color("#ffffff"), "muted": Color("#e6e6e6"), "accent": Color("#ffd400"),
				"accent_dim": Color("#bfa000"), "danger": Color("#ff7a6b"), "good": Color("#8cff8c"),
				"info": Color("#8fd3ff"), "paper": Color("#141414")}
	return {"bg": Color("#0f1116"), "panel": Color("#161921"), "card": Color("#1e222b"), "card_hi": Color("#282d38"),
			"line": Color("#363c4a"), "text": Color("#e8e2d4"), "muted": Color("#a59f92"), "accent": Color("#d9a441"),
			"accent_dim": Color("#7d6230"), "danger": Color("#d9705f"), "good": Color("#8bbf7f"),
			"info": Color("#86aecf"), "paper": Color("#25211a")}


static func box(bg: Color, border: Color, border_w := 0, radius := 6, margin := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func build(settings: Dictionary) -> Theme:
	var hc: bool = settings.get("high_contrast", false)
	var p := palette(hc)
	var base: int = SIZES[clampi(int(settings.get("text_size", 1)), 0, SIZES.size() - 1)]
	var t := Theme.new()
	t.default_font_size = base
	var bw := 2 if hc else 1

	# --- text
	t.set_color("font_color", "Label", p["text"])
	for v in [["TitleLabel", int(base * 2.0), p["accent"]], ["HeadingLabel", int(base * 1.35), p["text"]],
			["SubheadingLabel", int(base * 1.1), p["accent"]], ["MutedLabel", base, p["muted"]],
			["SmallLabel", max(14, int(base * 0.85)), p["muted"]], ["AccentLabel", base, p["accent"]],
			["DangerLabel", base, p["danger"]], ["GoodLabel", base, p["good"]], ["InfoLabel", base, p["info"]]]:
		t.set_type_variation(v[0], "Label")
		t.set_font_size("font_size", v[0], v[1])
		t.set_color("font_color", v[0], v[2])
	t.set_color("default_color", "RichTextLabel", p["text"])
	t.set_font_size("normal_font_size", "RichTextLabel", base)
	t.set_font_size("bold_font_size", "RichTextLabel", base)

	# --- panels
	t.set_stylebox("panel", "PanelContainer", box(p["panel"], p["line"], 0, 0, 0))
	for v in [["Backdrop", box(p["bg"], p["bg"], 0, 0, 0)], ["Sidebar", box(p["panel"], p["line"], 0, 0, 14)],
			["Card", box(p["card"], p["line"], bw, 8, 16)], ["CardHi", box(p["card_hi"], p["accent_dim"], bw, 8, 16)],
			["Paper", box(p["paper"], p["accent_dim"], bw, 4, 14)], ["TopBar", box(p["panel"], p["line"], 0, 0, 10)],
			["Bubble", box(p["card_hi"], p["line"], bw, 10, 12)], ["Warning", box(p["card"], p["danger"], 2, 6, 10)]]:
		t.set_type_variation(v[0], "PanelContainer")
		t.set_stylebox("panel", v[0], v[1])

	# --- buttons
	t.set_stylebox("normal", "Button", box(p["card_hi"], p["line"], bw, 6, 10))
	t.set_stylebox("hover", "Button", box(p["card_hi"].lightened(0.08), p["accent"], bw, 6, 10))
	t.set_stylebox("pressed", "Button", box(p["accent_dim"], p["accent"], bw, 6, 10))
	t.set_stylebox("disabled", "Button", box(p["card"], p["line"], bw, 6, 10))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), p["accent"], 2, 6, 10))
	for c in ["font_color", "font_focus_color", "font_hover_color"]:
		t.set_color(c, "Button", p["text"])
	t.set_color("font_pressed_color", "Button", p["text"])
	t.set_color("font_hover_pressed_color", "Button", p["text"])
	t.set_color("font_disabled_color", "Button", p["muted"].darkened(0.25))
	for v in [["PrimaryButton", p["accent_dim"], p["accent"]], ["NavButton", p["panel"], p["panel"]],
			["DangerButton", p["card_hi"], p["danger"]], ["TopicButton", p["card"], p["line"]]]:
		t.set_type_variation(v[0], "Button")
		t.set_stylebox("normal", v[0], box(v[1], v[2], bw, 6, 10))
		t.set_stylebox("hover", v[0], box(v[1].lightened(0.1), p["accent"], bw, 6, 10))
	t.set_font_size("font_size", "PrimaryButton", int(base * 1.1))
	t.set_stylebox("pressed", "NavButton", box(p["card_hi"], p["accent"], bw, 6, 10))
	t.set_stylebox("normal", "NavButtonActive", box(p["card_hi"], p["accent"], 2, 6, 10))
	t.set_type_variation("NavButtonActive", "Button")
	t.set_color("font_color", "NavButtonActive", p["accent"])
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(k, "CheckBox", StyleBoxEmpty.new())
		t.set_stylebox(k, "CheckButton", StyleBoxEmpty.new())

	# --- inputs, menus, dialogs, tooltips
	for ty in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", ty, box(p["card"], p["line"], bw, 6, 10))
		t.set_stylebox("focus", ty, box(p["card"], p["accent"], 2, 6, 10))
		t.set_color("font_color", ty, p["text"])
		t.set_color("font_placeholder_color", ty, p["muted"])
		t.set_color("caret_color", ty, p["accent"])
	t.set_stylebox("panel", "PopupMenu", box(p["card"], p["line"], bw, 6, 8))
	t.set_stylebox("hover", "PopupMenu", box(p["accent_dim"], p["accent_dim"], 0, 4, 6))
	t.set_color("font_color", "PopupMenu", p["text"])
	t.set_color("font_hover_color", "PopupMenu", p["text"])
	t.set_stylebox("panel", "AcceptDialog", box(p["card"], p["line"], 0, 0, 16))
	t.set_stylebox("embedded_border", "Window", box(p["card"], p["accent_dim"], 2, 8, 0))
	t.set_color("title_color", "Window", p["accent"])
	t.set_stylebox("panel", "TooltipPanel", box(p["card_hi"], p["accent_dim"], 1, 6, 10))
	t.set_color("font_color", "TooltipLabel", p["text"])
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	var sep := StyleBoxLine.new()
	sep.color = p["line"]
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_constant("h_separation", "HFlowContainer", 8)
	t.set_constant("v_separation", "HFlowContainer", 8)
	t.set_stylebox("background", "ProgressBar", box(p["card"], p["line"], 0, 4, 0))
	t.set_stylebox("fill", "ProgressBar", box(p["accent"], p["accent"], 0, 4, 0))
	return t
