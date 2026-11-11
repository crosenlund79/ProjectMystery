## The investigation: case file, people, places, records, notebook, timeline and theory.
## Presentation only - every rule lives in scripts/core/investigation.gd. Each action autosaves.
extends Control

const Kit = preload("res://scripts/ui/kit.gd")
const Clock = preload("res://scripts/core/clock.gd")
const TimelineChart = preload("res://scripts/ui/timeline_chart.gd")
const Investigation = preload("res://scripts/core/investigation.gd")

const PAGES := [
	["case", "Case file", "What happened, when and where, and how far you have got"],
	["people", "People", "Talk to the residents"],
	["places", "Places", "Look around town, and at the vehicles"],
	["records", "Records", "Ledgers, bar tabs, clinic notes and job books"],
	["notebook", "Notebook", "Everything you have found, and your own notes"],
	["timeline", "Timeline", "Discovered events in order, with conflicting accounts flagged"],
	["theory", "Solve the case", "Put forward your theory, or give up and see the truth"],
]
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
const MARKS := [["No mark", ""], ["Confirmed", "confirmed"], ["Disputed", "disputed"], ["Uncertain", "uncertain"],
		["My inference", "inference"]]
const FILTERS := [["All", ""], ["Statements", "statement"], ["Evidence", "trace"], ["Records", "record"],
		["Observations", "observation"], ["My notes", "note"]]
const SOURCE_NAMES := {"statement": "statement", "trace": "evidence", "record": "record", "observation": "observation",
		"note": "your note"}
const KIND_NAMES := {"square": "Public square", "road": "Road", "shop": "Shop", "pub": "Public house",
		"workshop": "Workshop", "clinic": "Clinic", "mill": "Mill", "home": "Private home"}

var app
var engine
var page := "case"
var content: VBoxContainer
var nav := {}
var credits_label: Label
var hint_button: Button
var selected_resident := ""
var selected_place := ""
var selected_book := ""
var book_day := 0
var notebook_filter := ""
var timeline_person := ""
var timeline_selected := ""
var last_answer := {}
var theory_cites := {}
var theory_widgets := {}


func _init(app_, engine_) -> void:
	app = app_
	engine = engine_
	var ui: Dictionary = engine.state["ui"]
	for k in ["dialogue", "searched", "read"]:
		if typeof(ui.get(k)) != TYPE_DICTIONARY:
			ui[k] = {}
	page = ui.get("page", "case")
	if page == "theory":
		page = "case"


func _ready() -> void:
	var bg := Kit.panel("Backdrop")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := Kit.vbox(0)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bg.add_child(root)
	root.add_child(_top_bar())
	var body := Kit.hbox(0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var side := Kit.panel("Sidebar")
	side.size_flags_horizontal = Control.SIZE_FILL
	side.custom_minimum_size = Vector2(220, 0)
	var sv := Kit.vbox(8)
	for pg in PAGES:
		var b := Kit.button(pg[1], pg[2], "NavButton", "Nav_" + pg[0])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(show_page.bind(pg[0]))
		sv.add_child(b)
		nav[pg[0]] = b
	side.add_child(sv)
	body.add_child(side)
	content = Kit.vbox(12)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var holder := Kit.margin(content, 20)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(holder)
	refresh_credits()
	show_page(page)


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
			["%s  ·  you arrive %s" % [engine.data["town"], engine.data["start_label"]], "SmallLabel"]]:
		var l := Kit.label(line[0], line[1], false)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.tooltip_text = line[0]
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		titles.add_child(l)
	tb.add_child(titles)
	credits_label = Kit.label("", "AccentLabel", false)
	credits_label.tooltip_text = "Investigation credits pay for hints. Each credit spent costs 5 points."
	credits_label.mouse_filter = Control.MOUSE_FILTER_STOP
	tb.add_child(credits_label)
	hint_button = Kit.button("Ask for a hint", "Spend investigation credits on a hint", "", "HintButton")
	hint_button.pressed.connect(ask_hint)
	tb.add_child(hint_button)
	var solve := Kit.button("Solve the case…", "Put forward your theory, or give up and see the truth", "PrimaryButton",
			"TheoryButton")
	solve.pressed.connect(show_page.bind("theory"))
	tb.add_child(solve)
	top.add_child(tb)
	return top


func refresh_credits() -> void:
	credits_label.text = "Credits: %d" % int(engine.state["credits"])
	var cost = engine.next_hint_cost()
	hint_button.disabled = cost == null or int(engine.state["credits"]) < int(cost)
	hint_button.tooltip_text = "No more hints for this case." if cost == null else \
			"Next hint costs %d credit(s); each credit costs 5 points." % int(cost)


func show_page(name_: String) -> void:
	page = name_
	for k in nav:
		nav[k].theme_type_variation = "NavButtonActive" if k == name_ else "NavButton"
	Kit.clear(content)
	match name_:
		"people":
			_page_people()
		"places":
			_page_places()
		"records":
			_page_records()
		"notebook":
			_page_notebook()
		"timeline":
			_page_timeline()
		"theory":
			_page_theory()
		_:
			_page_case()
	engine.state["ui"]["page"] = name_
	app.persist()


func _title(text: String, sub := "") -> void:
	content.add_child(Kit.label(text, "TitleLabel"))
	if sub != "":
		content.add_child(Kit.label(sub, "MutedLabel"))


func _name(rid) -> String:
	if rid == null:
		return "no one"
	var r: Dictionary = engine.resident(rid)
	return r.get("name", str(rid))


# =========================================================================== case file
func _page_case() -> void:
	var hook: Dictionary = engine.data["hook"]
	_title("Case file")
	var list := Kit.vbox(14)
	var card := Kit.panel("Paper")
	var v := Kit.vbox(8)
	v.add_child(Kit.label(hook["title"], "HeadingLabel"))
	v.add_child(Kit.label(hook["text"]))
	v.add_child(Kit.label("The time in question: " + hook["window_label"], "AccentLabel"))
	v.add_child(Kit.label("Where: " + engine.place_name(hook["place"]), "AccentLabel"))
	v.add_child(Kit.label("Reported by: " + _name(hook["discovered_by"]), "MutedLabel"))
	card.add_child(v)
	list.add_child(card)
	list.add_child(_info_card("Who you are", engine.data["player_role"]))
	var alive := 0
	for r in engine.data["residents"]:
		if r["condition"] != "deceased":
			alive += 1
	var places_total: int = engine.data["places"].size() + engine.data["vehicles"].size()
	var tl: Dictionary = engine.timeline()
	var progress := "People questioned: %d of %d\nPlaces and vehicles examined: %d of %d\nNotebook entries: %d\nConflicting accounts spotted: %d" % [
			engine.state["goodwill"].size(), alive, engine.state["ui"]["searched"].size(), places_total,
			engine.state["entries"].size(), tl["conflicts"].size()]
	list.add_child(_info_card("Your progress", progress))
	if not engine.state["ui_hints"].is_empty():
		var lines := PackedStringArray()
		for h in engine.state["ui_hints"]:
			lines.append("%s: %s" % [h["label"], h["text"]])
		list.add_child(_info_card("Hints you have bought", "\n\n".join(lines)))
	list.add_child(_info_card("How to investigate",
			"Ask people where they were and what they saw. Testimony tells you what someone believes: people misremember, repeat rumours, protect those they love - and whoever is responsible may lie.\n\n"
			+ "Look around public places; private homes, back rooms and record books need their owner's agreement, and a refusal can tell you something too.\n\n"
			+ "Everything you learn goes into the notebook. The timeline lines up who was where, and flags accounts that cannot both be true.\n\n"
			+ "When you are ready, choose 'Solve the case'. 'Cannot be determined' is an honest answer when the evidence is thin."))
	content.add_child(Kit.scroll(list))


func _info_card(title: String, body: String) -> Control:
	var card := Kit.panel("Card")
	var v := Kit.vbox(6)
	v.add_child(Kit.label(title, "SubheadingLabel"))
	v.add_child(Kit.label(body))
	card.add_child(v)
	return card


# =========================================================================== people
func _page_people() -> void:
	_title("People", "Choose someone, then pick what to ask. Their answers are filed in your notebook.")
	var split := Kit.hbox(16)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := Kit.vbox(6)
	for r in engine.data["residents"]:
		var extra := ""
		if r["condition"] == "deceased":
			extra = "  ·  deceased"
		elif r["condition"] == "injured":
			extra = "  ·  injured"
		if engine.state["ui"]["dialogue"].has(r["id"]):
			extra += "  ·  spoken to"
		var b := Kit.button("%s\n%s%s" % [r["name"], r["occupation"], extra], "Talk to %s" % r["first"], "NavButton",
				"Resident_" + r["id"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if r["id"] == selected_resident:
			b.theme_type_variation = "NavButtonActive"
		b.pressed.connect(select_resident.bind(r["id"]))
		list.add_child(b)
	var left := Kit.scroll(list)
	left.custom_minimum_size = Vector2(280, 0)
	left.size_flags_horizontal = Control.SIZE_FILL
	split.add_child(left)
	var right := Kit.vbox(10)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if selected_resident == "":
		right.add_child(Kit.label("Choose someone to talk to.", "MutedLabel"))
	else:
		_conversation(right)
	split.add_child(right)
	content.add_child(split)


func select_resident(rid: String) -> void:
	selected_resident = rid
	if last_answer.get("speaker", "") != rid:
		last_answer = {}
	show_page("people")


func _conversation(box: VBoxContainer) -> void:
	var rid := selected_resident
	var r: Dictionary = engine.resident(rid)
	var card := Kit.panel("Card")
	var v := Kit.vbox(4)
	v.add_child(Kit.label(r["name"], "HeadingLabel"))
	var home: String = engine.place_name(r["home"])
	v.add_child(Kit.label("%s, %s  ·  lives at %s" % [String(r["occupation"]).capitalize(), r["age_group"], home], "MutedLabel"))
	var t = engine.data["testimony"].get(rid)
	if t != null:
		var gw := int(engine.state["goodwill"].get(rid, t["goodwill"]))
		var full := maxi(gw, int(t["goodwill"]))
		var meter := Kit.label("Patience: " + "●".repeat(gw) + "○".repeat(maxi(0, full - gw)), "SmallLabel", false)
		meter.tooltip_text = "Pressing someone who is holding back costs patience. When it runs out, they stop talking."
		meter.mouse_filter = Control.MOUSE_FILTER_STOP
		v.add_child(meter)
	card.add_child(v)
	box.add_child(card)
	if r["condition"] == "deceased":
		box.add_child(Kit.label("%s is dead. You can still ask other people about them." % r["first"], "MutedLabel"))
		return
	var topics := Kit.flow()
	for t_ in Investigation.BASE_TOPICS:
		var b := Kit.button(t_[1], QUESTIONS[t_[0]], "TopicButton", "Topic_" + t_[0])
		b.pressed.connect(ask.bind(rid, t_[0], false))
		topics.add_child(b)
	box.add_child(topics)
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
	box.add_child(about)
	if last_answer.get("speaker", "") == rid:
		var follow := Kit.flow()
		if last_answer.get("can_press", false):
			var press := Kit.button("Press them on this", "Costs 1 patience. Someone holding back may tell you more.",
					"DangerButton", "PressButton")
			press.pressed.connect(ask.bind(rid, last_answer["topic"], true))
			follow.add_child(press)
		var shown := 0
		for x in last_answer.get("followups", []):
			if shown >= 4:
				break
			var b := Kit.button("Ask about %s" % engine.first_name(x), "Follow up on someone they mentioned", "TopicButton",
					"FollowUp_" + x)
			b.pressed.connect(ask.bind(rid, "person:" + x, false))
			follow.add_child(b)
			shown += 1
		if follow.get_child_count() > 0:
			box.add_child(Kit.label("Follow up:", "SmallLabel"))
			box.add_child(follow)
	var history := Kit.vbox(10)
	var history_log: Array = engine.state["ui"]["dialogue"].get(rid, [])
	if history_log.is_empty():
		history.add_child(Kit.label("You have not spoken to %s yet." % r["first"], "MutedLabel"))
	for i in range(history_log.size() - 1, -1, -1):
		history.add_child(_exchange(history_log[i], r["first"]))
	box.add_child(Kit.scroll(history))


func _exchange(ex: Dictionary, first: String) -> Control:
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
			tag.tooltip_text = "Filed in your notebook as " + Kit.tag_text(line["notes"])
			tag.mouse_filter = Control.MOUSE_FILTER_STOP
			row.add_child(tag)
		v.add_child(row)
	bubble.add_child(v)
	return bubble


func _ask_about(rid: String, opt: OptionButton, ids: Array) -> void:
	if opt.selected >= 0 and opt.selected < ids.size():
		ask(rid, "person:" + String(ids[opt.selected]), false)


func question_text(rid: String, topic: String, press: bool) -> String:
	if press:
		return "I think there's more you're not telling me about that."
	if topic.begins_with("person:"):
		return "What can you tell me about %s?" % engine.first_name(topic.substr(7))
	return QUESTIONS.get(topic, engine.topic_label(rid, topic))


func ask(rid: String, topic: String, press := false) -> Dictionary:
	var res: Dictionary = engine.ask(rid, topic, press)
	if res.has("error"):
		app.message("You can't ask that", String(res["error"]))
		return res
	var dialogue: Dictionary = engine.state["ui"]["dialogue"]
	if not dialogue.has(rid):
		dialogue[rid] = []
	dialogue[rid].append({"q": question_text(rid, topic, press), "topic": topic, "pressed": press,
			"lines": res["lines"]})
	last_answer = res
	selected_resident = rid
	app.persist()
	show_page("people")
	return res


# =========================================================================== places
func _page_places() -> void:
	_title("Places", "Look around town. Private places need the owner's agreement.")
	var split := Kit.hbox(16)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := Kit.vbox(6)
	for p in engine.data["places"]:
		list.add_child(_place_button(p["id"], p["name"], KIND_NAMES.get(p["kind"], p["kind"])))
	list.add_child(Kit.spacer(6))
	list.add_child(Kit.label("Vehicles", "SubheadingLabel"))
	for veh in engine.data["vehicles"]:
		list.add_child(_place_button(veh["id"], veh["name"], "parked at " + engine.place_name(veh["location"])))
	var left := Kit.scroll(list)
	left.custom_minimum_size = Vector2(300, 0)
	left.size_flags_horizontal = Control.SIZE_FILL
	split.add_child(left)
	var right := Kit.vbox(10)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if selected_place == "":
		right.add_child(Kit.label("Choose a place or a vehicle.", "MutedLabel"))
	elif not engine.vehicle(selected_place).is_empty():
		_vehicle_detail(right)
	else:
		_place_detail(right)
	split.add_child(right)
	content.add_child(split)


func _place_button(id: String, title: String, sub: String) -> Button:
	var mark := "  ✓" if engine.state["ui"]["searched"].has(id) else ""
	var b := Kit.button("%s%s\n%s" % [title, mark, sub], "Examine " + title, "NavButton", "Place_" + id.replace(":", "_"))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if id == selected_place:
		b.theme_type_variation = "NavButtonActive"
	b.pressed.connect(select_place.bind(id))
	return b


func select_place(id: String) -> void:
	selected_place = id
	show_page("places")


func _owners_text(owners: Array) -> String:
	if owners.is_empty():
		return "Open to anyone."
	var names := PackedStringArray()
	for o in owners:
		names.append(_name(o))
	return "Belongs to " + ", ".join(names) + "."


func _place_detail(box: VBoxContainer) -> void:
	var p: Dictionary = engine.place(selected_place)
	var card := Kit.panel("Card")
	var v := Kit.vbox(6)
	v.add_child(Kit.label(p["name"], "HeadingLabel"))
	v.add_child(Kit.label("%s  ·  %s" % [KIND_NAMES.get(p["kind"], p["kind"]), _owners_text(p["owners"])], "MutedLabel"))
	var done = engine.state["ui"]["searched"].get(selected_place)
	if done == null:
		var private_: bool = not p["owners"].is_empty()
		var b := Kit.button("Ask to look around" if private_ else "Look around",
				"Ask the owner's permission and search" if private_ else "Search the place", "PrimaryButton", "SearchButton")
		b.pressed.connect(search_place.bind(selected_place))
		v.add_child(b)
	card.add_child(v)
	box.add_child(card)
	if done != null:
		box.add_child(Kit.scroll(_search_result(done)))


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
		for k in res.get("books", []):
			var book: Dictionary = engine.data["records"][k]
			var b := Kit.button("Read the %s" % String(book["title"]).to_lower(), "Open this record book", "TopicButton",
					"OpenBook_" + k)
			b.pressed.connect(open_book.bind(k))
			v.add_child(b)
		for vid in res.get("vehicles", []):
			var b := Kit.button("Look at %s, parked here" % engine.vehicle(vid)["name"], "Examine the vehicle",
					"TopicButton", "OpenVehicle_" + vid)
			b.pressed.connect(select_place.bind(vid))
			v.add_child(b)
	else:
		v.add_child(Kit.label("Refused. Noted in your notebook as %s." % res["note"], "SmallLabel"))
	return v


func search_place(pid: String) -> Dictionary:
	var res: Dictionary = engine.inspect_place(pid)
	if res.has("error"):
		app.message("You can't do that", String(res["error"]))
		return res
	engine.state["ui"]["searched"][pid] = res
	selected_place = pid
	app.persist()
	show_page("places")
	return res


func _vehicle_detail(box: VBoxContainer) -> void:
	var veh: Dictionary = engine.vehicle(selected_place)
	var card := Kit.panel("Card")
	var v := Kit.vbox(6)
	v.add_child(Kit.label(String(veh["name"]).capitalize(), "HeadingLabel"))
	v.add_child(Kit.label("A %s, parked at %s." % [veh["kind"], engine.place_name(veh["location"])], "MutedLabel"))
	var done = engine.state["ui"]["searched"].get(selected_place)
	if done == null:
		var b := Kit.button("Look it over", "Examine the vehicle (its owners must agree if it is parked at their home)",
				"PrimaryButton", "SearchButton")
		b.pressed.connect(search_vehicle.bind(selected_place))
		v.add_child(b)
	card.add_child(v)
	box.add_child(card)
	if done != null:
		box.add_child(Kit.scroll(_search_result(done)))


func search_vehicle(vid: String) -> Dictionary:
	var res: Dictionary = engine.inspect_vehicle(vid)
	if res.has("error"):
		app.message("You can't do that", String(res["error"]))
		return res
	res["show_reply"] = not res["allowed"]
	engine.state["ui"]["searched"][vid] = res
	selected_place = vid
	app.persist()
	show_page("places")
	return res


# =========================================================================== records
func open_book(key: String) -> void:
	selected_book = key
	book_day = 0
	show_page("records")


func _page_records() -> void:
	_title("Records", "Written records remember what people forget. Owners decide whether you may read them.")
	var split := Kit.hbox(16)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := Kit.vbox(6)
	var keys: Array = engine.data["records"].keys()
	keys.sort()
	for k in keys:
		var book: Dictionary = engine.data["records"][k]
		var b := Kit.button("%s\nkept at %s" % [book["title"], engine.place_name(book["place"])], "Open " + book["title"],
				"NavButton", "Book_" + k)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if k == selected_book:
			b.theme_type_variation = "NavButtonActive"
		b.pressed.connect(open_book.bind(k))
		list.add_child(b)
	var left := Kit.scroll(list)
	left.custom_minimum_size = Vector2(300, 0)
	left.size_flags_horizontal = Control.SIZE_FILL
	split.add_child(left)
	var right := Kit.vbox(10)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if selected_book == "":
		right.add_child(Kit.label("Choose a record book.", "MutedLabel"))
	else:
		_book_detail(right)
	split.add_child(right)
	content.add_child(split)


func read_book(key: String) -> Dictionary:
	var res: Dictionary = engine.read(key)
	if res.has("error"):
		app.message("You can't do that", String(res["error"]))
		return res
	engine.state["ui"]["read"][key] = {"allowed": res["allowed"], "reply": res["reply"]}
	selected_book = key
	app.persist()
	show_page("records")
	return res


func _book_detail(box: VBoxContainer) -> void:
	var book: Dictionary = engine.data["records"][selected_book]
	box.add_child(Kit.label(book["title"], "HeadingLabel"))
	var seen = engine.state["ui"]["read"].get(selected_book)
	if seen == null:
		var b := Kit.button("Ask to read it", "Ask the owner of %s for permission" % engine.place_name(book["place"]),
				"PrimaryButton", "ReadButton")
		b.pressed.connect(read_book.bind(selected_book))
		box.add_child(b)
		return
	if not seen["allowed"]:
		var w := Kit.panel("Warning")
		w.add_child(Kit.label(seen["reply"]))
		box.add_child(w)
		return
	var entries: Array = book["entries"]
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
	var row := Kit.hbox()
	row.add_child(Kit.label("Show:", "", false))
	var opt := Kit.option(days, sel, "Show one day at a time")
	opt.name = "BookDay"
	opt.item_selected.connect(_pick_day.bind(days))
	row.add_child(opt)
	box.add_child(row)
	var list := Kit.vbox(6)
	for e in entries:
		if book_day != 0 and Clock.day_of(e["time"]) != book_day:
			continue
		var line := Kit.hbox(10)
		line.add_child(Kit.label(String(e["text"])))
		var copied: bool = engine.state["by_ref"].has(e["id"])
		var c := Kit.button("In notebook" if copied else "Copy to notebook",
				"Add this line to your notebook so you can cite it" if not copied else "Already in your notebook",
				"TopicButton", "Cite_" + String(e["id"]).replace("#", "_").replace("-", "_"))
		c.disabled = copied
		c.pressed.connect(cite.bind(e["id"]))
		line.add_child(c)
		list.add_child(line)
	if list.get_child_count() == 0:
		list.add_child(Kit.label("No entries for that period.", "MutedLabel"))
	box.add_child(Kit.scroll(list))


func _pick_day(index: int, days: Array) -> void:
	book_day = int(days[index][1])
	show_page("records")


func cite(entry_id: String) -> void:
	engine.cite_record(entry_id)
	app.persist()
	show_page("records")


# =========================================================================== notebook
func _conflict_map() -> Dictionary:
	var out := {}
	for e in engine.timeline()["entries"]:
		if not e["conflicts"].is_empty():
			out[e["id"]] = e["conflicts"]
	return out


func _page_notebook() -> void:
	_title("Notebook", "Everything you have found. Mark what you believe, and add your own notes.")
	var add := Kit.panel("Card")
	var av := Kit.vbox(8)
	var line := LineEdit.new()
	line.name = "NoteText"
	line.placeholder_text = "Write a note…"
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av.add_child(line)
	var row := Kit.flow()
	row.add_theme_constant_override("h_separation", 8)
	var timed := CheckBox.new()
	timed.name = "NoteTimed"
	timed.text = "Put it on the timeline at"
	row.add_child(timed)
	var start := int(engine.data["hook"]["window"][0])
	var day := _spin("NoteDay", 1, 99, Clock.day_of(start), "Day")
	var hour := _spin("NoteHour", 0, 23, Clock.idiv(start % 1440, 60), "Hour")
	var minute := _spin("NoteMinute", 0, 59, start % 60, "Minute")
	for w in [Kit.label("Day", "", false), day, Kit.label("time", "", false), hour, Kit.label(":", "", false), minute]:
		row.add_child(w)
	var btn := Kit.button("Add note", "Add this note to your notebook", "PrimaryButton", "AddNoteButton")
	btn.pressed.connect(_add_note.bind(line, timed, day, hour, minute))
	row.add_child(btn)
	av.add_child(row)
	add.add_child(av)
	content.add_child(add)
	var filters := Kit.flow()
	for f in FILTERS:
		var b := Kit.button(f[0], "Show " + String(f[0]).to_lower(), "NavButtonActive" if f[1] == notebook_filter else "NavButton",
				"Filter_" + (f[1] if f[1] != "" else "all"))
		b.pressed.connect(_set_filter.bind(f[1]))
		filters.add_child(b)
	content.add_child(filters)
	var conflicts := _conflict_map()
	var list := Kit.vbox(8)
	var shown := 0
	for e in engine.state["entries"]:
		if notebook_filter != "" and e["source"] != notebook_filter:
			continue
		list.add_child(_entry_card(e, conflicts.get(e["id"], [])))
		shown += 1
	if shown == 0:
		list.add_child(Kit.label("Nothing here yet. Talk to people, look around and read the records.", "MutedLabel"))
	content.add_child(Kit.scroll(list))


func _spin(name_: String, lo: int, hi: int, value: int, tip: String) -> SpinBox:
	var s := SpinBox.new()
	s.name = name_
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = value
	s.tooltip_text = tip
	return s


func _add_note(line: LineEdit, timed: CheckBox, day: SpinBox, hour: SpinBox, minute: SpinBox) -> void:
	var text := line.text.strip_edges()
	if text == "":
		return
	var t = null
	if timed.button_pressed:
		t = (int(day.value) - 1) * 1440 + int(hour.value) * 60 + int(minute.value)
	add_note(text, t)


func add_note(text: String, time = null) -> String:
	var id: String = engine.note(text, time)
	app.persist()
	show_page(page)
	return id


func _set_filter(f: String) -> void:
	notebook_filter = f
	show_page("notebook")


func _entry_card(e: Dictionary, conflicts: Array) -> Control:
	var card := Kit.panel("Paper" if e["source"] == "note" else "Card")
	var v := Kit.vbox(4)
	var head := Kit.hbox(10)
	head.add_child(Kit.label("[%s]" % e["id"], "AccentLabel", false))
	var when := Clock.fmt(e["time"]) if e["time"] != null else "no time"
	head.add_child(Kit.label("%s  ·  %s" % [SOURCE_NAMES.get(e["source"], e["source"]), when], "SmallLabel"))
	var marks := []
	var sel := 0
	for i in range(MARKS.size()):
		marks.append([MARKS[i][0], i])
		if MARKS[i][1] == (e["mark"] if e["mark"] != null else ""):
			sel = i
	var opt := Kit.option(marks, sel, "How much do you trust this?")
	opt.name = "Mark_" + String(e["id"])
	opt.item_selected.connect(_set_mark.bind(e["id"]))
	head.add_child(opt)
	v.add_child(head)
	v.add_child(Kit.label(String(e["text"])))
	if not conflicts.is_empty():
		v.add_child(Kit.label("⚠ Conflicts with " + ", ".join(PackedStringArray(conflicts))
				+ " — they cannot all be true.", "DangerLabel"))
	card.add_child(v)
	return card


func _set_mark(index: int, eid: String) -> void:
	if MARKS[index][1] == "":
		engine.clear_mark(eid)
	else:
		engine.mark(eid, MARKS[index][1])
	app.persist()


# =========================================================================== timeline
func _page_timeline() -> void:
	_title("Timeline", "Who was where, according to what you have been told. ⚠ marks accounts that put someone in two places at once — someone is mistaken, or lying.")
	var tl: Dictionary = engine.timeline()
	var people := {}
	for f in tl["facts"]:
		people[f["who"]] = true
	var ids: Array = people.keys()
	ids.sort()
	var opts := [["Everyone", 0]]
	var sel := 0
	for i in range(ids.size()):
		opts.append([_name(ids[i]), i + 1])
		if ids[i] == timeline_person:
			sel = i + 1
	var row := Kit.hbox()
	row.add_child(Kit.label("Show:", "", false))
	var opt := Kit.option(opts, sel, "Follow one person")
	opt.name = "TimelinePerson"
	opt.item_selected.connect(_pick_person.bind(ids))
	row.add_child(opt)
	row.add_child(Kit.label("%d conflicting account(s) found" % tl["conflicts"].size(),
			"DangerLabel" if not tl["conflicts"].is_empty() else "SmallLabel", false))
	content.add_child(row)
	var chart = TimelineChart.new()
	chart.name = "TimelineChart"
	chart.high_contrast = bool(app.settings.get("high_contrast", false))
	chart.setup(tl, engine, timeline_person, timeline_selected)
	chart.entry_selected.connect(_pick_entry)
	content.add_child(chart)
	if timeline_selected != "":
		var e: Dictionary = engine.entry(timeline_selected)
		if not e.is_empty():
			var sel_card := Kit.panel("CardHi")
			sel_card.add_child(Kit.label("[%s]  %s" % [e["id"], e["text"]]))
			content.add_child(sel_card)
	var list := Kit.vbox(6)
	var about_person := {}
	for f in tl["facts"]:
		if f["who"] == timeline_person:
			about_person[f["entry"]] = true
	for e in tl["entries"]:
		if timeline_person != "" and not about_person.has(e["id"]):
			continue
		var line := Kit.hbox(10)
		var stamp := Kit.label(("≈ " if e["id"].begins_with("S") else "") + e["label"], "AccentLabel", false)
		stamp.custom_minimum_size = Vector2(150, 0)
		stamp.tooltip_text = "Witness times are approximate." if e["id"].begins_with("S") else ""
		stamp.mouse_filter = Control.MOUSE_FILTER_STOP
		line.add_child(stamp)
		var body := Kit.vbox(2)
		body.add_child(Kit.label("[%s] %s" % [e["id"], e["text"]] + ("  (%s)" % e["mark"] if e["mark"] != null else "")))
		if not e["conflicts"].is_empty():
			body.add_child(Kit.label("⚠ Conflicts with " + ", ".join(PackedStringArray(e["conflicts"])), "DangerLabel"))
		line.add_child(body)
		list.add_child(line)
	if tl["entries"].is_empty():
		list.add_child(Kit.label("Nothing with a time on it yet. Ask people where they were and what they saw.",
				"MutedLabel"))
	content.add_child(Kit.scroll(list))


func _pick_person(index: int, ids: Array) -> void:
	timeline_person = "" if index == 0 else String(ids[index - 1])
	show_page("timeline")


func _pick_entry(eid: String) -> void:
	timeline_selected = eid
	show_page("timeline")


# =========================================================================== theory
func _page_theory() -> void:
	_title("Solve the case", "Say what you think happened. Submitting closes the investigation and reveals the truth.")
	var form := Kit.vbox(12)
	var card := Kit.panel("Card")
	var v := Kit.vbox(10)
	var mechs: Array = engine.mechanisms()
	var mitems := []
	for i in range(mechs.size()):
		mitems.append([mechs[i]["label"], i])
	theory_widgets["mechanism"] = _field(v, "What happened?", Kit.option(mitems, 0, "Your explanation"), "TheoryMechanism")
	var ritems := [["No one / not applicable", 0]]
	var rids := [null]
	for r in engine.data["residents"]:
		ritems.append([r["name"], ritems.size()])
		rids.append(r["id"])
	theory_widgets["responsible"] = _field(v, "Who is responsible?", Kit.option(ritems, 0, "The person you hold responsible"),
			"TheoryResponsible")
	theory_widgets["rids"] = rids
	var motives: Array = engine.motives()
	var motive_items := []
	var unknown := 0
	for i in range(motives.size()):
		motive_items.append([motives[i]["label"], i])
		if motives[i]["id"] == "unknown":
			unknown = i
	theory_widgets["motive"] = _field(v, "Why?", Kit.option(motive_items, unknown, "The motive, if any"), "TheoryMotive")
	card.add_child(v)
	form.add_child(card)
	var ev_card := Kit.panel("Card")
	var ev := Kit.vbox(6)
	ev.add_child(Kit.label("Evidence that supports your theory (optional)", "SubheadingLabel"))
	ev.add_child(Kit.label("Citing reliable evidence earns points; leaning on lies or mistakes costs them.", "SmallLabel"))
	var any := false
	for e in engine.state["entries"]:
		var line := Kit.hbox(6)
		var cb := CheckBox.new()
		cb.name = "TheoryCite_" + String(e["id"])
		cb.text = "[%s]" % e["id"]
		cb.tooltip_text = "Cite this as evidence"
		cb.button_pressed = theory_cites.has(e["id"])
		cb.toggled.connect(_toggle_cite.bind(e["id"]))
		line.add_child(cb)
		line.add_child(Kit.label(String(e["text"])))
		ev.add_child(line)
		any = true
	if not any:
		ev.add_child(Kit.label("Your notebook is empty.", "MutedLabel"))
	ev_card.add_child(ev)
	form.add_child(ev_card)
	var summary := TextEdit.new()
	summary.name = "TheorySummary"
	summary.placeholder_text = "In your own words: what happened?"
	summary.custom_minimum_size = Vector2(0, 90)
	summary.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	theory_widgets["summary"] = summary
	form.add_child(summary)
	var buttons := Kit.hbox(12)
	var submit := Kit.button("Submit my theory", "Close the case with this theory and see the truth", "PrimaryButton",
			"SubmitTheoryButton")
	submit.pressed.connect(_confirm_submit)
	buttons.add_child(submit)
	var give := Kit.button("Give up and see the truth", "Close the case without a theory", "DangerButton", "GiveUpButton")
	give.pressed.connect(Callable(app, "confirm").bind("Give up?", "The case will close and the truth will be revealed.", give_up,
			"Give up"))
	buttons.add_child(give)
	form.add_child(buttons)
	content.add_child(Kit.scroll(form))


func _field(box: VBoxContainer, label: String, opt: OptionButton, name_: String) -> OptionButton:
	var row := Kit.hbox(12)
	var l := Kit.label(label, "", false)
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	opt.name = name_
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(opt)
	box.add_child(row)
	return opt


func _toggle_cite(on: bool, eid: String) -> void:
	if on:
		theory_cites[eid] = true
	else:
		theory_cites.erase(eid)


func _confirm_submit() -> void:
	app.confirm("Submit your theory?", "The investigation will close and the truth will be revealed.", submit_from_form,
			"Submit")


func submit_from_form() -> void:
	var mechs: Array = engine.mechanisms()
	var motives: Array = engine.motives()
	var rids: Array = theory_widgets["rids"]
	var cites: Array = []
	for e in engine.state["entries"]:
		if theory_cites.has(e["id"]):
			cites.append(e["id"])
	submit_theory(mechs[theory_widgets["mechanism"].selected]["id"], rids[theory_widgets["responsible"].selected],
			motives[theory_widgets["motive"].selected]["id"], cites, theory_widgets["summary"].text)


func submit_theory(mechanism: String, responsible, motive: String, cites: Array, summary: String) -> Dictionary:
	var res: Dictionary = engine.submit(mechanism, responsible, motive, cites, summary)
	if res.has("error"):
		app.message("Your theory was not accepted", String(res["error"]))
		return res
	_finish()
	return res


func give_up() -> void:
	engine.give_up()
	_finish()


func _finish() -> void:
	var res: Dictionary = engine.reveal()
	app.show_reveal(res["model"])


# =========================================================================== hints
func ask_hint() -> void:
	var cost = engine.next_hint_cost()
	if cost == null:
		app.message("No more hints", "There are no more hints for this case.")
		return
	app.confirm("Ask for a hint?", "This hint costs %d credit(s). Every credit spent lowers your final score by 5 points." % int(cost),
			buy_hint, "Spend %d" % int(cost))


func buy_hint() -> Dictionary:
	var res: Dictionary = engine.hint()
	app.persist()
	refresh_credits()
	if res.get("ok", false):
		app.message(res["label"], res["text"])
	else:
		app.message("No hint", String(res.get("message", "")))
	if page == "case":
		show_page("case")
	return res
