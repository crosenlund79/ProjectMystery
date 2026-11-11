## The truth, revealed only after the player concluded the case: what happened, the score,
## the real sequence of events, the player's notebook checked against the truth, and the
## leads they missed.
extends Control

const Kit = preload("res://scripts/ui/kit.gd")

var app
var engine
var model: Dictionary


func _init(app_, engine_, model_: Dictionary) -> void:
	app = app_
	engine = engine_
	model = model_


func _ready() -> void:
	var bg := Kit.panel("Backdrop")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := Kit.vbox(14)
	col.custom_minimum_size = Vector2(760, 0)
	var top := Kit.hbox()
	var back := Kit.button("◂ Main menu", "Return to the main menu", "", "RevealMenuButton")
	back.pressed.connect(Callable(app, "show_main_menu"))
	top.add_child(back)
	var cases := Kit.button("Choose another case", "Back to the case list", "", "RevealNewCaseButton")
	cases.pressed.connect(Callable(app, "show_new_case"))
	top.add_child(cases)
	col.add_child(top)
	col.add_child(Kit.label("THE TRUTH", "TitleLabel"))
	col.add_child(Kit.label(engine.data["hook"]["title"], "MutedLabel"))
	var story := Kit.panel("Paper")
	var narrative := Kit.label(model["narrative"], "HeadingLabel")
	narrative.name = "Narrative"
	story.add_child(narrative)
	col.add_child(story)
	col.add_child(_comparison())
	col.add_child(_score())
	col.add_child(_section("What actually happened", _timeline()))
	col.add_child(_section("Your notebook, checked against the truth", _annotations()))
	if not model["missed"].is_empty():
		var v := Kit.vbox(4)
		for m in model["missed"]:
			v.add_child(Kit.label("• %s (%s)%s" % [_kind(m["type"]), m["source"],
					" — they needed pressing" if m["needs_pressing"] else ""]))
		col.add_child(_section("Leads you did not follow", v))
	var a := Kit.panel("Card")
	a.add_child(Kit.label("Case assessment: " + String(model["assessment"]), "MutedLabel"))
	col.add_child(a)
	var center := CenterContainer.new()
	center.add_child(col)
	var scroller := Kit.scroll(Kit.margin(center, 24))
	scroller.name = "RevealScroll"
	bg.add_child(scroller)
	back.call_deferred("grab_focus")


func _kind(t: String) -> String:
	return {"witness": "A witness", "physical": "A physical trace", "documentary": "A written record",
			"contradiction": "A contradiction"}.get(t, t)


func _section(title: String, body: Control) -> Control:
	var card := Kit.panel("Card")
	var v := Kit.vbox(8)
	v.add_child(Kit.label(title, "SubheadingLabel"))
	v.add_child(body)
	card.add_child(v)
	return card


func _comparison() -> Control:
	var ans: Dictionary = model["answer"]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	var th = model["theory"]
	for cell in ["", "What really happened", "Your theory"]:
		grid.add_child(Kit.label(cell, "SubheadingLabel", false))
	var rows := [["What happened", ans["mechanism"], "mechanism"], ["Who", ans["responsible"], "responsible"],
			["Why", ", ".join(PackedStringArray(ans["motives"])), "motive"]]
	for row in rows:
		grid.add_child(Kit.label(row[0], "MutedLabel", false))
		grid.add_child(Kit.label(String(row[1]), "", false))
		var mine := "—" if th == null else String(th[row[2]])
		var good := th != null and (mine == String(row[1]) or (row[2] == "motive" and ans["motives"].has(mine)))
		grid.add_child(Kit.label(mine, "GoodLabel" if good else ("DangerLabel" if th != null else "MutedLabel"), false))
	var card := Kit.panel("Card")
	var v := Kit.vbox(8)
	v.add_child(grid)
	v.add_child(Kit.label("Outcome: " + String(ans["outcome"]), "MutedLabel"))
	if th == null:
		v.add_child(Kit.label("You gave up without a theory.", "MutedLabel"))
	card.add_child(v)
	return card


func _score() -> Control:
	var sc: Dictionary = model["score"]
	var card := Kit.panel("CardHi")
	var v := Kit.vbox(8)
	var total := Kit.label("Score: %d / 100" % int(sc["total"]), "TitleLabel")
	total.name = "ScoreTotal"
	v.add_child(total)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = int(sc["total"])
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	v.add_child(bar)
	for part in sc["parts"]:
		var pts := int(part[1])
		v.add_child(Kit.label("%s: %s%d" % [String(part[0]).capitalize(), "+" if pts >= 0 else "", pts],
				"GoodLabel" if pts > 0 else ("DangerLabel" if pts < 0 else "MutedLabel")))
	for n in sc["notes"]:
		v.add_child(Kit.label("• " + String(n)))
	card.add_child(v)
	return card


func _timeline() -> Control:
	var v := Kit.vbox(4)
	for ev in model["timeline"]:
		var row := Kit.hbox(12)
		var stamp := Kit.label(ev["label"], "AccentLabel", false)
		stamp.custom_minimum_size = Vector2(150, 0)
		row.add_child(stamp)
		row.add_child(Kit.label(ev["summary"]))
		v.add_child(row)
	return v


func _annotations() -> Control:
	var v := Kit.vbox(8)
	if model["annotations"].is_empty():
		v.add_child(Kit.label("Nothing in your notebook bore on the case.", "MutedLabel"))
	for a in model["annotations"]:
		var card := Kit.panel("Card")
		var c := Kit.vbox(4)
		c.add_child(Kit.label("[%s]%s %s" % [a["entry"], " (cited)" if a["cited"] else "", a["text"]]))
		var verdict := String(a["verdict"])
		var style := "GoodLabel"
		if verdict.begins_with("LIE"):
			style = "DangerLabel"
		elif verdict.begins_with("MISTAKEN"):
			style = "AccentLabel"
		elif not verdict.begins_with("true"):
			style = "InfoLabel"
		c.add_child(Kit.label("→ " + verdict, style))
		card.add_child(c)
		v.add_child(card)
	if int(model["plain_true"]) > 0:
		v.add_child(Kit.label("…and %d other statement(s) you collected were true but beside the point." % int(model["plain_true"]),
				"MutedLabel"))
	return v
