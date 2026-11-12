## The investigation, in two layers.
##  * The town (world layer): a small map of every place in the case. Click a building to go there,
##    or a person you have seen to go and talk to them. The panel beside the map is where you are:
##    who is here, looking around, the record books kept here, the vehicles parked here, and your
##    conversations.
##  * The tablet (personal layer, T to open and close): case notes, notebook, evidence, people,
##    timeline, theory, hints and your case files. See tablet.gd.
## Presentation only - the rules live in scripts/core (investigation.gd, town.gd). Each action autosaves.
extends Control

const Kit = preload("res://scripts/ui/kit.gd")
const Clock = preload("res://scripts/core/clock.gd")
const Investigation = preload("res://scripts/core/investigation.gd")
const Town = preload("res://scripts/core/town.gd")
const TownMap = preload("res://scripts/ui/town_map.gd")
const PlaceArt = preload("res://scripts/ui/place_art.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")
const Faces = preload("res://scripts/core/expression.gd")
const ArtLib = preload("res://scripts/core/art.gd")
const Tablet = preload("res://scripts/ui/tablet.gd")

const QUESTIONS := {
	"whereabouts": "Where were you during that time?",
	"window": "Did you see or hear anything then?",
	"incident": "What do you know about what happened?",
	"money": "Is anyone having money troubles? Debts?",
	"conflicts": "Any arguments or grudges I should know about?",
	"rumors": "What are people saying?",
	"vehicles": "Anything about the vehicles, or the road?",
	"past": "Has there been other trouble in town lately?",
}
## Follow-up questions after an answer (free; pressing is the one that costs patience).
const FOLLOW_BUTTONS := {"more": "Tell me more", "earlier": "And before that?"}
## Short button labels for the topics (the full question is the tooltip and goes in the conversation).
const TOPIC_BUTTONS := {
	"whereabouts": "Where were you?",
	"window": "What did you see or hear?",
	"incident": "What happened?",
	"money": "Money troubles?",
	"conflicts": "Arguments or grudges?",
	"rumors": "What are people saying?",
	"vehicles": "Vehicles and the road",
	"past": "Other trouble lately?",
}

var app
var engine
var town
var map
var tablet
var panel: VBoxContainer
var where_label: Label
var credits_label: Label
var tablet_button: Button
var view := "place"
var talking := ""
var book := ""
var book_day := 0
var vehicle_id := ""
var banner := ""
var last_answer := {}
var faces := {}            # resident -> the face they are showing you now
var chime: AudioStreamPlayer


func _init(app_, engine_) -> void:
	app = app_
	engine = engine_
	var ui: Dictionary = engine.state["ui"]
	for k in ["dialogue", "searched", "read"]:
		if typeof(ui.get(k)) != TYPE_DICTIONARY:
			ui[k] = {}
	town = Town.new(engine)
	if not town.arrived():
		town.go(town.start_place())
		banner = "arrival"
	view = String(ui.get("view", "place"))
	talking = String(ui.get("talking", ""))
	book = String(ui.get("book", ""))
	vehicle_id = String(ui.get("vehicle", ""))
	if (view == "talk" and not town.is_here(talking)) or (view == "book" and town.record_place(book) != town.at()) \
			or (view == "vehicle" and not town.vehicles_at(town.at()).has(vehicle_id)) \
			or not ["place", "talk", "book", "vehicle"].has(view):
		view = "place"


func _ready() -> void:
	var bg := Kit.panel("Backdrop")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := Kit.vbox(0)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bg.add_child(root)
	root.add_child(_top_bar())
	var body := Kit.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map = TownMap.new()
	map.setup(town, engine, bool(app.settings.get("high_contrast", false)))
	map.size_flags_stretch_ratio = 1.7
	map.place_chosen.connect(go_to)
	map.person_chosen.connect(find_person)
	body.add_child(map)
	var side := Kit.panel("Sidebar")
	side.name = "LocationPanel"
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.custom_minimum_size = Vector2(360, 0)
	panel = Kit.vbox(10)
	side.add_child(Kit.scroll(panel))
	body.add_child(side)
	var holder := Kit.margin(body, 14)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(holder)
	tablet = Tablet.new(self)
	add_child(tablet)
	chime = AudioStreamPlayer.new()
	chime.name = "IntuitionChime"
	chime.stream = ArtLib.sound("sounds/intuition")
	add_child(chime)
	refresh()
	if engine.state["ui"].get("tablet", false):
		open_tablet(String(engine.state["ui"].get("tablet_page", "case")))


func _top_bar() -> Control:
	var top := Kit.panel("TopBar")
	var tb := Kit.hbox(14)
	var menu := Kit.button("◂ Menu", "Save and return to the main menu", "", "MenuButton")
	menu.pressed.connect(Callable(app, "show_main_menu"))
	tb.add_child(menu)
	var hook: Dictionary = engine.data["hook"]
	var titles := Kit.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for line in [[hook["title"], "HeadingLabel"],
			["%s  ·  %s" % [engine.data["town"], engine.data["start_label"]], "SmallLabel"]]:
		var l := Kit.label(line[0], line[1], false)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.tooltip_text = line[0]
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		titles.add_child(l)
	tb.add_child(titles)
	where_label = Kit.label("", "AccentLabel", false)
	where_label.name = "WhereLabel"
	tb.add_child(where_label)
	credits_label = Kit.label("", "MutedLabel", false)
	credits_label.tooltip_text = "Investigation credits pay for hints (in your tablet). Each credit spent costs 5 points."
	credits_label.mouse_filter = Control.MOUSE_FILTER_STOP
	tb.add_child(credits_label)
	tablet_button = Kit.button("Open tablet  (T)", "Your case notes, notebook, evidence, people, timeline, theory and hints",
			"PrimaryButton", "TabletButton")
	tablet_button.pressed.connect(toggle_tablet)
	tb.add_child(tablet_button)
	top.add_child(tb)
	return top


func refresh() -> void:
	var ui: Dictionary = engine.state["ui"]
	ui["view"] = view
	ui["talking"] = talking
	ui["book"] = book
	ui["vehicle"] = vehicle_id
	where_label.text = "At " + engine.place_name(town.at())
	refresh_credits()
	map.rebuild()
	Kit.clear(panel)
	match view:
		"talk":
			_talk_view()
		"book":
			_book_view()
		"vehicle":
			_vehicle_view()
		_:
			_place_view()


func refresh_credits() -> void:
	credits_label.text = "Credits: %d" % int(engine.state["credits"])


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_T:
		toggle_tablet()
		accept_event()
	elif key.keycode == KEY_ESCAPE:
		if tablet.visible:
			close_tablet()
		elif view != "place":
			back_to_place()
		accept_event()


# =========================================================================== tablet
func toggle_tablet() -> void:
	if tablet.visible:
		close_tablet()
	else:
		open_tablet(String(engine.state["ui"].get("tablet_page", "case")))


func open_tablet(page := "case") -> void:
	engine.state["ui"]["tablet"] = true
	tablet_button.text = "Close tablet  (T)"
	tablet.open(page)
	app.persist()


func close_tablet() -> void:
	engine.state["ui"]["tablet"] = false
	tablet_button.text = "Open tablet  (T)"
	tablet.close()
	refresh()
	app.persist()


# =========================================================================== moving around
func go_to(pid: String) -> void:
	var leaving: bool = town.at() != pid
	banner = ""
	town.go(pid)
	view = "place"
	app.persist()
	refresh()
	if leaving:
		intuition()


func find_person(rid: String) -> Dictionary:
	## Go to someone you have seen (or try their home) and, if they are there, start talking.
	var res: Dictionary = town.find(rid)
	if res.has("error"):
		app.message("You can't do that", String(res["error"]))
		return res
	banner = String(res.get("message", ""))
	if res.get("found", false):
		_start_talking(rid)
	else:
		view = "place"
	if tablet.visible:
		close_tablet()
	app.persist()
	refresh()
	return res


func route_to_place(pid: String) -> void:
	if tablet.visible:
		close_tablet()
	go_to(pid)


func route_to_book(key: String) -> void:
	var pid: String = town.record_place(key)
	if not town.has_place(pid):
		return
	if tablet.visible:
		close_tablet()
	banner = ""
	town.go(pid)
	book = key
	book_day = 0
	view = "book"
	app.persist()
	refresh()


func back_to_place() -> void:
	var was_talking := view == "talk"
	view = "place"
	banner = ""
	app.persist()
	refresh()
	if was_talking:
		intuition()


# =========================================================================== detective's intuition
func intuition() -> Dictionary:
	## Called on leaving a conversation or a place. A beginner hears a chime and is shown the two entries
	## worth comparing; a hobby detective only senses that something doesn't add up; experienced, nothing.
	var hit: Dictionary = engine.intuition()
	if hit.is_empty():
		return hit
	app.persist()
	var beginner: bool = engine.mode() == "beginner"
	if chime.stream != null:
		chime.volume_db = 0.0 if beginner else -14.0
		chime.play()
	var toast := Kit.panel("Paper" if beginner else "Card")
	toast.name = "IntuitionToast"
	var v := Kit.vbox(6)
	if beginner:
		v.add_child(Kit.label("Detective's intuition", "AccentLabel"))
		v.add_child(Kit.label("Something doesn't add up. Compare %s and %s in your notebook." % [hit["a"], hit["b"]]))
		var show_btn := Kit.button("Show me", "Open the notebook at the two entries", "PrimaryButton", "IntuitionShow")
		show_btn.pressed.connect(open_tablet.bind("notebook"))
		v.add_child(show_btn)
	else:
		v.add_child(Kit.label("Your intuition stirs: something you have heard doesn't add up.", "MutedLabel"))
	toast.add_child(v)
	toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	toast.position = Vector2(size.x - 420, 70)
	toast.custom_minimum_size = Vector2(380, 0)
	add_child(toast)
	get_tree().create_timer(9.0 if beginner else 5.0).timeout.connect(_drop_toast.bind(toast))
	return hit


func _drop_toast(toast: Control) -> void:
	if is_instance_valid(toast):
		toast.queue_free()


# =========================================================================== where you are
func _place_view() -> void:
	var pid: String = town.at()
	var p: Dictionary = town.place(pid)
	if banner == "arrival":
		panel.add_child(_arrival_card())
	elif banner != "":
		var w := Kit.panel("Warning")
		var msg := Kit.label(banner)
		msg.name = "Banner"
		w.add_child(msg)
		panel.add_child(w)
	var art = PlaceArt.View.new(String(p["kind"]), hash(pid), bool(app.settings.get("high_contrast", false)), map.dusk)
	art.place = p
	panel.add_child(art)
	panel.add_child(Kit.label(cap(String(p["name"])), "PlaceTitle"))
	panel.add_child(Kit.label("%s  ·  %s" % [TownMap.KIND_NAMES.get(p["kind"], p["kind"]), _owners_text(p["owners"])],
			"SmallLabel"))
	if pid == town.scene():
		var scene_note := Kit.panel("Warning")
		scene_note.add_child(Kit.label("This is where it happened: " + String(engine.data["hook"]["title"]), "DangerLabel"))
		panel.add_child(scene_note)

	_section("People here")
	var here: Array = town.people_here()
	if here.is_empty():
		panel.add_child(Kit.label("Nobody is here right now.", "MutedLabel"))
	for rid in here:
		var r: Dictionary = engine.resident(rid)
		var row := Kit.hbox(10)
		row.add_child(Portrait.new().setup(r, 52.0, String(faces.get(rid, Faces.at_rest(r)))))
		var who := Kit.vbox(0)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.add_child(Kit.label(r["name"], "SignLabel"))
		who.add_child(Kit.label(String(r["occupation"]) + ("  ·  injured" if r["condition"] == "injured" else ""), "SmallLabel"))
		row.add_child(who)
		var b := Kit.button("Talk", "Talk to %s" % r["first"], "TopicButton", "Talk_" + String(rid))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(talk_to.bind(rid))
		row.add_child(b)
		panel.add_child(row)

	_section("Look around")
	var done = engine.state["ui"]["searched"].get(pid)
	if done == null:
		var private_: bool = not p["owners"].is_empty()
		var look := Kit.button("Ask to look around" if private_ else "Look around",
				"Ask the owner's permission and search" if private_ else "Search the place", "PrimaryButton",
				"LookAroundButton")
		look.pressed.connect(look_around)
		panel.add_child(look)
	else:
		panel.add_child(_search_result(done))

	var books: Array = town.records_at(pid)
	if not books.is_empty():
		_section("Records kept here")
		for k in books:
			var bk: Dictionary = engine.data["records"][k]
			var seen = engine.state["ui"]["read"].get(k)
			var tag := ""
			if seen != null:
				tag = "  (you may read it)" if seen["allowed"] else "  (refused)"
			var brow := Kit.hbox(10)
			var bl := Kit.vbox(0)
			bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bl.add_child(Kit.label(String(bk["title"]), "SignLabel"))
			if tag != "":
				bl.add_child(Kit.label(tag.strip_edges().trim_prefix("(").trim_suffix(")"), "SmallLabel"))
			brow.add_child(bl)
			var rb := Kit.button("Read" if seen == null or seen["allowed"] else "Ask again", "Ask to read the %s" % String(bk["title"]).to_lower(),
					"TopicButton", "ReadBook_" + String(k))
			rb.pressed.connect(open_book.bind(k))
			brow.add_child(rb)
			panel.add_child(brow)

	var vehicles: Array = town.vehicles_at(pid)
	if not vehicles.is_empty():
		_section("Vehicles parked here")
		for vid in vehicles:
			var mark := "  ✓" if engine.state["ui"]["searched"].has(vid) else ""
			var vrow := Kit.hbox(10)
			vrow.add_child(Kit.label(cap(String(engine.vehicle(vid)["name"])) + mark, "SignLabel"))
			var vb := Kit.button("Examine", "Look the vehicle over", "TopicButton", "Examine_" + String(vid))
			vb.pressed.connect(open_vehicle.bind(vid))
			vrow.add_child(vb)
			panel.add_child(vrow)

	panel.add_child(Kit.spacer(6))
	panel.add_child(Kit.label("Click a building to walk there.  T opens your tablet.", "SmallLabel"))


func _section(title: String) -> void:
	panel.add_child(HSeparator.new())
	panel.add_child(Kit.label(title, "SubheadingLabel"))


static func initials(full_name: String) -> String:
	var parts := full_name.split(" ")
	return (parts[0].left(1) + (parts[parts.size() - 1].left(1) if parts.size() > 1 else "")).to_upper()


func medallion(full_name: String) -> Control:
	## A round initials badge, like the markers on the map.
	var m := Kit.panel("Medallion")
	m.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Kit.label(initials(full_name), "SignLabel", false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(30, 30)
	m.add_child(l)
	return m


func _arrival_card() -> Control:
	var hook: Dictionary = engine.data["hook"]
	var card := Kit.panel("Paper")
	card.name = "ArrivalCard"
	var v := Kit.vbox(6)
	v.add_child(Kit.label("You arrive in %s, %s." % [engine.data["town"], engine.data["start_label"]], "SmallLabel"))
	v.add_child(Kit.label(hook["title"], "HeadingLabel"))
	v.add_child(Kit.label(hook["text"]))
	v.add_child(Kit.label("The time in question: " + String(hook["window_label"]), "AccentLabel"))
	v.add_child(Kit.label("It happened at %s." % engine.place_name(town.scene()), "AccentLabel"))
	if town.scene() != town.at():
		var go := Kit.button("Go there", "Walk to %s" % engine.place_name(town.scene()), "PrimaryButton", "GoToScene")
		go.pressed.connect(go_to.bind(town.scene()))
		v.add_child(go)
	card.add_child(v)
	return card


func _owners_text(owners: Array) -> String:
	if owners.is_empty():
		return "Open to anyone"
	var names := PackedStringArray()
	for o in owners:
		names.append(engine.resident(o).get("name", str(o)))
	return "Belongs to " + ", ".join(names)


static func cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)


func _back_button() -> Button:
	var b := Kit.button("◂ Back to " + engine.place_name(town.at()), "Back (Esc)", "", "BackToPlace")
	b.pressed.connect(back_to_place)
	return b


func look_around() -> Dictionary:
	var res: Dictionary = town.look_around()
	if res.has("error"):
		app.message("You can't do that", String(res["error"]))
		return res
	engine.state["ui"]["searched"][town.at()] = res
	app.persist()
	refresh()
	return res


func _search_result(res: Dictionary) -> Control:
	var v := Kit.vbox(10)
	if res.get("show_reply", false) or not res["allowed"]:
		var reply := Kit.panel("Warning" if not res["allowed"] else "Bubble")
		reply.add_child(Kit.label(res["reply"]))
		v.add_child(reply)
	if res["allowed"]:
		if res["traces"].is_empty():
			v.add_child(Kit.label("Nothing out of the ordinary." if res["op"] == "inspect_place" else "Nothing unusual about it.",
					"MutedLabel"))
		for tr in res["traces"]:
			var c := Kit.panel("Paper")
			var row := Kit.vbox(4)
			row.add_child(Kit.label("Found  [%s]" % tr["note"], "SmallLabel"))
			row.add_child(Kit.label(tr["description"]))
			c.add_child(row)
			v.add_child(c)
	else:
		v.add_child(Kit.label("Refused. Noted in your tablet as %s." % res["note"], "SmallLabel"))
	return v


# =========================================================================== people
func talk_to(rid: String) -> void:
	if not town.is_here(rid):
		app.message("Not here", "%s isn't here." % engine.first_name(rid))
		return
	var switching := view == "talk" and talking != "" and talking != rid
	banner = ""
	_start_talking(rid)
	app.persist()
	refresh()
	if switching:
		intuition()


func _start_talking(rid: String) -> void:
	if talking != rid or last_answer.get("speaker", "") != rid:
		last_answer = {}
	talking = rid
	view = "talk"


func _talk_view() -> void:
	var rid := talking
	var r: Dictionary = engine.resident(rid)
	panel.add_child(_back_button())
	var card := Kit.panel("Card")
	var v := Kit.vbox(4)
	var head := Kit.hbox(12)
	var face := String(faces.get(rid, Faces.at_rest(r)))
	head.add_child(Portrait.new().setup(r, 112.0, face))
	var nm := Kit.label(r["name"], "PlaceTitle")
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	v.add_child(head)
	var home: String = engine.place_name(r["home"])
	v.add_child(Kit.label("%s, %s  ·  lives at %s" % [String(r["occupation"]).capitalize(), r["age_group"], home], "SmallLabel"))
	var read := Faces.caption(r, face, engine.mode())
	if read != "":
		var rl := Kit.label(read, "MutedLabel")
		rl.name = "FaceCaption"
		v.add_child(rl)
	var t = engine.data["testimony"].get(rid)
	if t != null:
		var gw := int(engine.state["goodwill"].get(rid, t["goodwill"]))
		var full := maxi(gw, int(t["goodwill"]))
		var meter := Kit.label("Patience: " + "●".repeat(gw) + "○".repeat(maxi(0, full - gw)), "SmallLabel", false)
		meter.tooltip_text = "Pressing someone who is holding back costs patience. When it runs out, they stop talking."
		meter.mouse_filter = Control.MOUSE_FILTER_STOP
		v.add_child(meter)
	card.add_child(v)
	panel.add_child(card)
	var topics := Kit.flow()
	for t_ in Investigation.BASE_TOPICS:
		var b := Kit.button(TOPIC_BUTTONS.get(t_[0], t_[1]), QUESTIONS[t_[0]], "TopicButton", "Topic_" + t_[0])
		b.pressed.connect(ask.bind(rid, t_[0], false))
		topics.add_child(b)
	panel.add_child(topics)
	var about := Kit.flow()
	about.add_child(Kit.label("Ask about someone:", "", false))
	var people := []
	var ids := []
	for o in engine.data["residents"]:
		if o["id"] != rid:
			people.append([o["name"], ids.size()])
			ids.append(o["id"])
	var opt := Kit.option(people, 0, "Choose who to ask about")
	opt.name = "AboutPerson"
	about.add_child(opt)
	var go := Kit.button("Ask", "Ask what they know about this person", "TopicButton", "AskAboutButton")
	go.pressed.connect(_ask_about.bind(rid, opt, ids))
	about.add_child(go)
	panel.add_child(about)
	if last_answer.get("speaker", "") == rid:
		var follow := Kit.flow()
		var last_topic := String(last_answer.get("topic", ""))
		if last_answer.get("can_more", false):
			var more := Kit.button(FOLLOW_BUTTONS["more"] if last_topic != "whereabouts" else "Can you be more exact?",
					"They summed some of that up. Free: it costs no patience.", "TopicButton", "MoreButton")
			more.pressed.connect(ask.bind(rid, last_topic, false, "more"))
			follow.add_child(more)
		if last_answer.get("can_earlier", false):
			var before := Kit.button(FOLLOW_BUTTONS["earlier"],
					"Go back before the time in question. Free: it costs no patience.", "TopicButton", "EarlierButton")
			before.pressed.connect(ask.bind(rid, last_topic, false, "earlier"))
			follow.add_child(before)
		if last_answer.get("can_press", false):
			var press := Kit.button("Press them on this", "Costs 1 patience. Someone holding back may tell you more.",
					"DangerButton", "PressButton")
			press.pressed.connect(ask.bind(rid, last_answer["topic"], true))
			follow.add_child(press)
		var shown := 0
		for x in last_answer.get("followups", []):
			if shown >= 4:
				break
			var fb := Kit.button("Ask about %s" % engine.first_name(x), "Follow up on someone they mentioned", "TopicButton",
					"FollowUp_" + x)
			fb.pressed.connect(ask.bind(rid, "person:" + x, false))
			follow.add_child(fb)
			shown += 1
		if follow.get_child_count() > 0:
			panel.add_child(Kit.label("Follow up:", "SmallLabel"))
			panel.add_child(follow)
	var history_log: Array = engine.state["ui"]["dialogue"].get(rid, [])
	if history_log.is_empty():
		panel.add_child(Kit.label("You have not spoken to %s yet." % r["first"], "MutedLabel"))
	for i in range(history_log.size() - 1, -1, -1):
		panel.add_child(exchange_card(history_log[i], r["first"]))


func exchange_card(ex: Dictionary, first: String) -> Control:
	var bubble := Kit.panel("Bubble")
	var v := Kit.vbox(6)
	v.add_child(Kit.label("You: " + String(ex["q"]), "AccentLabel"))
	var firstline := true
	for line in ex["lines"]:
		var row := Kit.hbox(8)
		var text := String(line["text"])
		var who := (first + ": ") if firstline else ""
		firstline = false
		row.add_child(Kit.label(who + text, "MutedLabel" if text.begins_with("(") else ""))
		if not line["notes"].is_empty():
			var tag := Kit.label("[" + Kit.tag_text(line["notes"]) + "]", "SmallLabel", false)
			tag.tooltip_text = "Filed in your tablet's notebook as " + Kit.tag_text(line["notes"])
			tag.mouse_filter = Control.MOUSE_FILTER_STOP
			row.add_child(tag)
		v.add_child(row)
	bubble.add_child(v)
	return bubble


func _ask_about(rid: String, opt: OptionButton, ids: Array) -> void:
	if opt.selected >= 0 and opt.selected < ids.size():
		ask(rid, "person:" + String(ids[opt.selected]), false)


func question_text(rid: String, topic: String, press: bool, follow := "") -> String:
	if press:
		return "I think there's more you're not telling me about that."
	if follow == "more":
		return "Can you be more exact?" if topic == "whereabouts" else "Tell me more about that."
	if follow == "earlier":
		return "And before that?"
	if topic.begins_with("person:"):
		return "What can you tell me about %s?" % engine.first_name(topic.substr(7))
	return QUESTIONS.get(topic, engine.topic_label(rid, topic))


func ask(rid: String, topic: String, press := false, follow := "") -> Dictionary:
	var res: Dictionary = town.ask(rid, topic, press, follow)
	if res.has("error"):
		app.message("You can't ask that", String(res["error"]))
		return res
	var t = engine.data["testimony"].get(rid)
	var reaction := Faces.react(engine.resident(rid), String(t["style"]) if t != null else "nervous", topic, res)
	faces[rid] = Faces.shown(engine.resident(rid), reaction, engine.mode())
	var dialogue: Dictionary = engine.state["ui"]["dialogue"]
	if not dialogue.has(rid):
		dialogue[rid] = []
	dialogue[rid].append({"q": question_text(rid, topic, press, follow), "topic": topic, "pressed": press,
			"follow": follow, "lines": res["lines"], "where": town.at()})
	last_answer = res
	talking = rid
	view = "talk"
	app.persist()
	refresh()
	return res


# =========================================================================== records
func open_book(key: String) -> void:
	if town.record_place(key) != town.at():
		route_to_book(key)
		return
	book = key
	book_day = 0
	view = "book"
	app.persist()
	refresh()


func read_book(key: String) -> Dictionary:
	var res: Dictionary = town.read(key)
	if res.has("error"):
		app.message("You can't do that", String(res["error"]))
		return res
	engine.state["ui"]["read"][key] = {"allowed": res["allowed"], "reply": res["reply"]}
	book = key
	view = "book"
	app.persist()
	refresh()
	return res


func _book_view() -> void:
	var bk: Dictionary = engine.data["records"][book]
	panel.add_child(_back_button())
	panel.add_child(Kit.label(bk["title"], "HeadingLabel"))
	panel.add_child(Kit.label("Kept at " + engine.place_name(bk["place"]), "MutedLabel"))
	var seen = engine.state["ui"]["read"].get(book)
	if seen == null:
		var b := Kit.button("Ask to read it", "Ask the owner of %s for permission" % engine.place_name(bk["place"]),
				"PrimaryButton", "ReadButton")
		b.pressed.connect(read_book.bind(book))
		panel.add_child(b)
		return
	if not seen["allowed"]:
		var w := Kit.panel("Warning")
		w.add_child(Kit.label(seen["reply"]))
		panel.add_child(w)
		return
	var entries: Array = bk["entries"]
	var days := [["All days", 0]]
	var day_set := {}
	for e in entries:
		day_set[Clock.day_of(e["time"])] = true
	var day_keys: Array = day_set.keys()
	day_keys.sort()
	for d in day_keys:
		days.append(["Day %d" % d, d])
	var sel := 0
	for i in range(days.size()):
		if days[i][1] == book_day:
			sel = i
	var row := Kit.flow()
	row.add_child(Kit.label("Show:", "", false))
	var opt := Kit.option(days, sel, "Show one day at a time")
	opt.name = "BookDay"
	opt.item_selected.connect(_pick_day.bind(days))
	row.add_child(opt)
	panel.add_child(row)
	var shown := 0
	for e in entries:
		if book_day != 0 and Clock.day_of(e["time"]) != book_day:
			continue
		var line := Kit.hbox(10)
		line.add_child(Kit.label(String(e["text"])))
		var copied: bool = engine.state["by_ref"].has(e["id"])
		var c := Kit.button("Copied" if copied else "Copy",
				"Copy this line into your tablet so you can cite it" if not copied else "Already in your tablet",
				"TopicButton", "Cite_" + String(e["id"]).replace("#", "_").replace("-", "_"))
		c.disabled = copied
		c.pressed.connect(cite.bind(e["id"]))
		line.add_child(c)
		panel.add_child(line)
		shown += 1
	if shown == 0:
		panel.add_child(Kit.label("No entries for that period.", "MutedLabel"))


func _pick_day(index: int, days: Array) -> void:
	book_day = int(days[index][1])
	refresh()


func cite(entry_id: String) -> void:
	engine.cite_record(entry_id)
	app.persist()
	refresh()


# =========================================================================== vehicles
func open_vehicle(vid: String) -> void:
	vehicle_id = vid
	view = "vehicle"
	app.persist()
	refresh()


func _vehicle_view() -> void:
	var veh: Dictionary = engine.vehicle(vehicle_id)
	panel.add_child(_back_button())
	panel.add_child(Kit.label(cap(String(veh["name"])), "HeadingLabel"))
	panel.add_child(Kit.label("A %s, parked at %s." % [veh["kind"], engine.place_name(veh["location"])], "MutedLabel"))
	var done = engine.state["ui"]["searched"].get(vehicle_id)
	if done == null:
		var b := Kit.button("Look it over", "Examine the vehicle (its owners must agree if it is parked at their home)",
				"PrimaryButton", "SearchButton")
		b.pressed.connect(search_vehicle.bind(vehicle_id))
		panel.add_child(b)
	else:
		panel.add_child(_search_result(done))


func search_vehicle(vid: String) -> Dictionary:
	var res: Dictionary = town.examine(vid)
	if res.has("error"):
		app.message("You can't do that", String(res["error"]))
		return res
	res["show_reply"] = not res["allowed"]
	engine.state["ui"]["searched"][vid] = res
	vehicle_id = vid
	view = "vehicle"
	app.persist()
	refresh()
	return res
