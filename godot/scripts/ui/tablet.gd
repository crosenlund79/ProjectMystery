## The investigator's tablet: the player's own tool for organising what they have learned.
## It opens over the town (T, or the Tablet button) and closes again (T, Esc, or Back to town).
## Pages: case notes, notebook, evidence, people, timeline, theory, hints and case files.
## Nothing here moves you around town except the explicit "Go to ..." buttons, which close the
## tablet and walk you there. Other case files are listed for the feel of a working tablet, but
## they are locked: nothing on this tablet can open another case while this one is open.
extends Control

const Kit = preload("res://scripts/ui/kit.gd")
const Clock = preload("res://scripts/core/clock.gd")
const TimelineChart = preload("res://scripts/ui/timeline_chart.gd")
const Investigation = preload("res://scripts/core/investigation.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")
const Expression = preload("res://scripts/core/expression.gd")

const PAGES := [
	["case", "Case notes", "What happened, when and where, and how far you have got"],
	["notebook", "Notebook", "Everything you have learned, with your marks and your own notes"],
	["evidence", "Evidence", "What you found in town and copied from records"],
	["people", "People", "Everyone in town: who they are, where you saw them, what they told you"],
	["timeline", "Timeline", "Discovered events in order, and what doesn't add up"],
	["theory", "Solve the case", "Put forward your theory, or give up and see the truth"],
	["hints", "Hints", "Spend investigation credits on a hint"],
	["files", "Case files", "The other cases on this tablet"],
]
const MARKS := [["No mark", ""], ["Confirmed", "confirmed"], ["Disputed", "disputed"], ["Uncertain", "uncertain"],
		["My inference", "inference"]]
const FILTERS := [["All", ""], ["Statements", "statement"], ["Evidence", "trace"], ["Records", "record"],
		["Observations", "observation"], ["My notes", "note"]]
## Evidence management: one-click status markers on every notebook entry.
const STATUS_BUTTONS := [["suspicious", "Suspicious", "Mark as suspicious - something here doesn't sit right"],
		["active", "Active", "Keep this in play - you are working on it"],
		["ignored", "Ignore", "Set it aside. It stays in your notebook under Review ignored, never deleted."]]
const STATUS_FILTERS := [["all", "Everything", "Everything except what you ignored"],
		["suspicious", "Suspicious", "Only what you marked suspicious"], ["active", "Active", "Only what you marked active"],
		["unmarked", "Unmarked", "What you have not marked yet"],
		["ignored", "Review ignored", "Everything you set aside, to reconsider"]]
const STATUS_CARDS := {"suspicious": "CardSuspicious", "active": "CardActive", "ignored": "CardIgnored"}
const VERDICT_TEXT := {
	"connected": ["✓ Connected to the incident", "GoodLabel"],
	"unrelated": ["✗ Not connected to the incident", "DangerLabel"],
	"uncertain": ["? Can't be settled by checking", "InfoLabel"],
}
const REASON_TEXT := {
	"web": "Checked against the record of what happened: this is part of the story. It doesn't say how, who did it, or whether anyone told the truth.",
	"outside": "Checked against the record of what happened: this has nothing to do with it.",
	"where_when": "It places someone where and when something to do with the incident happened. Whether that matters depends on who it was and whether it is true - that is for you to work out.",
	"untraced": "It can't be traced back to anything anyone actually saw or did, so there is nothing to check it against.",
}
const SOURCE_NAMES := {"statement": "statement", "trace": "evidence", "record": "record", "observation": "observation",
		"note": "your note"}

var screen
var app
var engine
var town
var page := "case"
var content: VBoxContainer
var nav := {}
var notebook_filter := ""
var status_filter := "all"
var show_ignored := false
var show_earlier := false
var show_minor := false
var mode_label: Label
var timeline_person := ""
var timeline_selected := ""
var person := ""
var theory_cites := {}
var theory_widgets := {}


func _init(screen_) -> void:
	screen = screen_
	app = screen.app
	engine = screen.engine
	town = screen.town
	name = "Tablet"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := Kit.panel("Dim")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var frame := Kit.panel("TabletFrame")
	frame.name = "TabletFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP]:
		frame.set_offset(side, 14)
	for side in [SIDE_RIGHT, SIDE_BOTTOM]:
		frame.set_offset(side, -14)
	add_child(frame)
	var glass := Kit.panel("TabletScreen")
	frame.add_child(glass)
	var col := Kit.vbox(0)
	glass.add_child(col)
	var bar := Kit.panel("TabletBar")
	var bh := Kit.hbox(12)
	var tag := Kit.label("CASE TABLET", "SmallLabel", false)
	bh.add_child(tag)
	var title := Kit.label("%s  ·  %s" % [engine.data["hook"]["title"], engine.data["town"]], "AccentLabel", false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bh.add_child(title)
	mode_label = Kit.label("", "SmallLabel", false)
	mode_label.name = "ModeLabel"
	mode_label.mouse_filter = Control.MOUSE_FILTER_STOP
	bh.add_child(mode_label)
	_refresh_mode_label()
	bh.add_child(Kit.label("Saved automatically", "SmallLabel", false))
	var close_b := Kit.button("Back to town  (T)", "Put the tablet away", "PrimaryButton", "CloseTablet")
	close_b.pressed.connect(Callable(screen, "close_tablet"))
	bh.add_child(close_b)
	bar.add_child(bh)
	col.add_child(bar)
	var body := Kit.hbox(0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	var side_v := Kit.vbox(6)
	side_v.size_flags_horizontal = Control.SIZE_FILL
	side_v.custom_minimum_size = Vector2(170, 0)
	for pg in PAGES:
		var b := Kit.button(pg[1], pg[2], "NavButton", "TabletNav_" + pg[0])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(show_page.bind(pg[0]))
		side_v.add_child(b)
		nav[pg[0]] = b
	side_v.add_child(Kit.grow())
	var save_exit := Kit.button("Save and quit to menu", "Your investigation is saved; Continue picks it up again",
			"", "SaveExitButton")
	save_exit.pressed.connect(Callable(app, "show_main_menu"))
	side_v.add_child(save_exit)
	body.add_child(Kit.margin(side_v, 10))
	content = Kit.vbox(12)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var holder := Kit.margin(content, 14)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(holder)


func open(pg := "case") -> void:
	visible = true
	show_page(pg if pg != "" else "case")


func close() -> void:
	visible = false


func show_page(name_: String) -> void:
	var known := false
	for pg in PAGES:
		if pg[0] == name_:
			known = true
	page = name_ if known else "case"
	for k in nav:
		nav[k].theme_type_variation = "NavButtonActive" if k == page else "NavButton"
	Kit.clear(content)
	match page:
		"notebook":
			_page_notebook()
		"evidence":
			_page_evidence()
		"people":
			_page_people()
		"timeline":
			_page_timeline()
		"theory":
			_page_theory()
		"hints":
			_page_hints()
		"files":
			_page_files()
		_:
			_page_case()
	engine.state["ui"]["tablet_page"] = page
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


func _info_card(title: String, body: String) -> Control:
	var card := Kit.panel("Card")
	var v := Kit.vbox(6)
	v.add_child(Kit.label(title, "SubheadingLabel"))
	v.add_child(Kit.label(body))
	card.add_child(v)
	return card


# =========================================================================== case notes
func _page_case() -> void:
	var hook: Dictionary = engine.data["hook"]
	_title("Case notes")
	var list := Kit.vbox(14)
	var card := Kit.panel("Paper")
	var v := Kit.vbox(8)
	v.add_child(Kit.label(hook["title"], "HeadingLabel"))
	v.add_child(Kit.label(hook["text"]))
	v.add_child(Kit.label("The time in question: " + hook["window_label"], "AccentLabel"))
	v.add_child(Kit.label("Where: " + engine.place_name(hook["place"]), "AccentLabel"))
	v.add_child(Kit.label("Reported by: " + _name(hook["discovered_by"]), "MutedLabel"))
	if town.at() != town.scene():
		var go := Kit.button("Go to %s" % engine.place_name(town.scene()), "Close the tablet and walk to the scene", "TopicButton",
				"GoToScene")
		go.pressed.connect(Callable(screen, "route_to_place").bind(town.scene()))
		v.add_child(go)
	card.add_child(v)
	list.add_child(card)
	list.add_child(_info_card("Who you are", engine.data["player_role"]))
	var alive := 0
	for r in engine.data["residents"]:
		if r["condition"] != "deceased":
			alive += 1
	var tl: Dictionary = engine.timeline()
	var counts := _status_counts()
	var progress := "You are at %s.\nPlaces visited: %d of %d\nPeople questioned: %d of %d\nNotebook entries: %d (suspicious %d, active %d, ignored %d)\nAccounts that don't add up: %d" % [
			engine.place_name(town.at()), engine.state["ui"]["visited"].size(), town.places().size(),
			engine.state["goodwill"].size(), alive, engine.state["entries"].size(), counts["suspicious"], counts["active"],
			counts["ignored"], _real(tl["contradictions"]).size()]
	progress += "\n" + String(Investigation.MODE_LABELS[engine.mode()])
	if engine.can_check():
		progress += ": %d of %d checks left" % [engine.strikes_left(), Investigation.MAX_STRIKES]
	list.add_child(_info_card("Your progress", progress))
	list.add_child(_info_card("How to investigate",
			"Walk around town: click a building on the map to go there. You meet whoever is there, and the people you have seen stay marked on the map. Click one of them to go back and talk.\n\n"
			+ "Testimony tells you what someone believes. People misremember, repeat rumours and protect those they love, and whoever is responsible may lie.\n\n"
			+ "People answer the way people do: about the time in question, with everyday things summed up. Ask them to tell you more for the details, ask 'and before that?' to go further back, or ask about one person in particular. Only pressing costs patience.\n\n"
			+ "Look around each place. Record books are kept where they belong: the ledger at the shop, the bar tabs at the pub, the patient log at the clinic. Private places and their books need the owner's agreement, and a refusal can tell you something too.\n\n"
			+ "Sort what you learn as you go: mark it Suspicious, Active, or Ignore it (ignored things are never deleted - Review ignored brings them back)."
			+ (" You can check anything you marked suspicious: you learn whether it is connected to the incident, never who did it or whether anyone lied. Three wrong calls and the checks are gone; right ones are free.\n\n" if engine.can_check() else "\n\n")
			+ ("When you leave a conversation or a place, your detective's intuition may tell you that two things you have found don't add up%s.\n\n" % (" - and which two" if engine.mode() == "beginner" else "") if engine.mode() != "experienced" else "")
			+ "Everything you learn lands in this tablet. The timeline lines up who was where and flags accounts that cannot both be true. When you are ready, open 'Solve the case'. 'Cannot be determined' is an honest answer when the evidence is thin."))
	content.add_child(Kit.scroll(list))


# =========================================================================== notebook
func _conflict_map() -> Dictionary:
	var out := {}
	for e in engine.timeline()["entries"]:
		if not e["conflicts"].is_empty():
			out[e["id"]] = e["conflicts"]
	return out


func _page_notebook() -> void:
	_title("Notebook", "Everything you have learned. Mark what you believe, and add your own notes.")
	var add := Kit.panel("Card")
	var av := Kit.vbox(8)
	var line := LineEdit.new()
	line.name = "NoteText"
	line.placeholder_text = "Write a note…"
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av.add_child(line)
	var row := Kit.flow()
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
	var counts := _status_counts()
	var sf := Kit.flow()
	for f in STATUS_FILTERS:
		var label: String = f[1] if f[0] == "all" else "%s (%d)" % [f[1], counts.get(f[0], 0)]
		var b := Kit.button(label, f[2], "NavButtonActive" if f[0] == status_filter else "NavButton", "StatusFilter_" + f[0])
		b.pressed.connect(_set_status_filter.bind(f[0]))
		sf.add_child(b)
	content.add_child(sf)
	if status_filter == "ignored":
		var note := Kit.panel("Paper")
		note.name = "IgnoredNotice"
		note.add_child(Kit.label("What you set aside. Nothing here has been deleted: restore anything that deserves another look.",
				"MutedLabel"))
		content.add_child(note)
	var conflicts := _conflict_map()
	var pair: Array = engine.state["intuition"].get("pair", [])
	if engine.mode() == "beginner" and pair.size() == 2:
		content.add_child(_intuition_card(pair))
	var list := Kit.vbox(8)
	list.name = "EntryList"
	var shown := 0
	for e in engine.state["entries"]:
		if not _shows(e):
			continue
		list.add_child(_entry_card(e, conflicts.get(e["id"], [])))
		shown += 1
	if shown == 0:
		list.add_child(Kit.label("Nothing here." if not engine.state["entries"].is_empty() else
				"Nothing here yet. Talk to people, look around and read the records.", "MutedLabel"))
	content.add_child(Kit.scroll(list))


func _status_counts() -> Dictionary:
	var out := {"suspicious": 0, "active": 0, "ignored": 0, "unmarked": 0}
	for e in engine.state["entries"]:
		var st: String = engine.status_of(String(e["id"]))
		out[st if st != "" else "unmarked"] += 1
	return out


func _shows(e: Dictionary) -> bool:
	## Does the notebook's current source and status filter show this entry?
	if notebook_filter != "" and e["source"] != notebook_filter:
		return false
	var st: String = engine.status_of(String(e["id"]))
	match status_filter:
		"all":
			return st != "ignored"
		"unmarked":
			return st == ""
		_:
			return st == status_filter


func _set_status_filter(f: String) -> void:
	status_filter = f
	show_page("notebook")


func review_ignored() -> void:
	notebook_filter = ""
	status_filter = "ignored"
	show_page("notebook")


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


func _intuition_card(pair: Array) -> Control:
	## Absolute Beginner: the two entries their intuition says to compare - not what to make of them.
	var card := Kit.panel("CardHi")
	card.name = "IntuitionCard"
	var v := Kit.vbox(6)
	v.add_child(Kit.label("Your detective's intuition: compare these two", "AccentLabel"))
	for eid in pair:
		var e: Dictionary = engine.entry(String(eid))
		v.add_child(Kit.label("[%s]  %s" % [eid, e.get("text", "")]))
	var row := Kit.flow()
	var tl := Kit.button("Line them up on the timeline", "Open the timeline", "TopicButton", "IntuitionTimeline")
	tl.pressed.connect(show_page.bind("timeline"))
	row.add_child(tl)
	var done := Kit.button("Got it", "Put this away", "TopicButton", "IntuitionDone")
	done.pressed.connect(_intuition_done)
	row.add_child(done)
	v.add_child(row)
	card.add_child(v)
	return card


func _intuition_done() -> void:
	engine.state["intuition"]["pair"] = []
	app.persist()
	show_page("notebook")


func _entry_card(e: Dictionary, conflicts: Array) -> Control:
	var eid := String(e["id"])
	var card := Kit.panel(STATUS_CARDS.get(engine.status_of(eid), "Paper" if e["source"] == "note" else "Card"))
	card.name = "Entry_" + eid
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
	if engine.mode() == "beginner" and engine.state["intuition"].get("pair", []).has(eid):
		v.add_child(Kit.label("Your intuition says to compare this with %s." % ", ".join(PackedStringArray(
				engine.state["intuition"]["pair"].filter(func(x): return x != eid))), "AccentLabel"))
	if e["ref"] != null and engine.is_summary(String(e["ref"])):
		v.add_child(Kit.label("This sums up several things they told you. Ask them to tell you more for the details.",
				"MutedLabel"))
	if not conflicts.is_empty():
		v.add_child(Kit.label("⚠ Doesn't add up with " + ", ".join(PackedStringArray(conflicts))
				+ " — see the timeline.", "DangerLabel"))
	v.add_child(_status_row(eid))
	card.add_child(v)
	return card


func _status_row(eid: String) -> Control:
	## One click marks an entry suspicious, active or ignored; clicking the lit one clears it.
	## Hobby Detective can check what they marked suspicious.
	var row := Kit.flow()
	var st: String = engine.status_of(eid)
	for s_ in STATUS_BUTTONS:
		var b := Kit.button(s_[1], s_[2], "NavButtonActive" if st == s_[0] else "TopicButton", "Status_%s_%s" % [eid, s_[0]])
		b.pressed.connect(set_status.bind(eid, "" if st == s_[0] else s_[0]))
		row.add_child(b)
	if st == "ignored":
		var r := Kit.button("Restore", "Bring it back into play", "PrimaryButton", "Restore_" + eid)
		r.pressed.connect(set_status.bind(eid, ""))
		row.add_child(r)
	if engine.can_check() and engine.checkable(eid):
		var done = engine.state["checks"].get(eid)
		if done != null:
			row.add_child(verdict_label(eid, String(done["verdict"]), String(done["reason"])))
		elif st == "suspicious":
			var c := Kit.button("Check it", "Is this connected to the incident? A wrong call costs one of your three strikes; a right one is free.",
					"PrimaryButton", "Check_" + eid)
			c.disabled = engine.strikes_left() == 0
			if c.disabled:
				c.tooltip_text = "No checks left: three of your calls were wrong."
			c.pressed.connect(check.bind(eid))
			row.add_child(c)
	return row


func verdict_label(eid: String, verdict: String, reason: String) -> Label:
	var vt: Array = VERDICT_TEXT.get(verdict, ["?", "SmallLabel"])
	var l := Kit.label(vt[0], vt[1], false)
	l.name = "Verdict_" + eid
	l.tooltip_text = String(REASON_TEXT.get(reason, ""))
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


func set_status(eid: String, status: String) -> void:
	if not engine.set_status(eid, status):
		return
	app.persist()
	_after_status(eid)


func _after_status(eid: String) -> void:
	## Update just this entry where it is shown, so the list keeps its scroll position.
	if page == "timeline":
		show_page("timeline")
		return
	var old = content.find_child("Entry_" + eid, true, false)
	if old == null or (page == "notebook" and not _shows(engine.entry(eid))) \
			or (page == "evidence" and engine.status_of(eid) == "ignored"):
		show_page(page)
		return
	var parent: Node = old.get_parent()
	var idx: int = old.get_index()
	parent.remove_child(old)
	old.queue_free()
	var fresh := _entry_card(engine.entry(eid), _conflict_map().get(eid, []))
	parent.add_child(fresh)
	parent.move_child(fresh, idx)
	_refresh_filter_counts()


func _refresh_filter_counts() -> void:
	var counts := _status_counts()
	for f in STATUS_FILTERS:
		var b = content.find_child("StatusFilter_" + f[0], true, false)
		if b != null and f[0] != "all":
			b.text = "%s (%d)" % [f[1], counts.get(f[0], 0)]


func check(eid: String) -> Dictionary:
	## Hobby Detective: ask whether a suspicious item is connected to the incident.
	var res: Dictionary = engine.check(eid)
	app.persist()
	if res.has("error"):
		app.message("Can't check that", String(res["error"]))
		return res
	_refresh_mode_label()
	var vt: Array = VERDICT_TEXT.get(String(res["verdict"]), ["?", ""])
	var body := String(REASON_TEXT.get(String(res["reason"]), ""))
	if res["strike"]:
		body += "\n\nThat was a wrong call: strike %d of %d." % [int(res["strikes"]), Investigation.MAX_STRIKES]
		if int(res["left"]) == 0:
			body += " You have no checks left - from here on you judge alone."
	app.message(String(vt[0]).substr(2), body)
	_after_status(eid)
	return res


func _refresh_mode_label() -> void:
	if mode_label == null:
		return
	var label := String(Investigation.MODE_LABELS[engine.mode()])
	if engine.can_check():
		mode_label.text = label + ("  ·  %d of %d checks left" % [engine.strikes_left(), Investigation.MAX_STRIKES] \
				if engine.strikes_left() > 0 else "  ·  no checks left")
		mode_label.tooltip_text = "Check anything you marked suspicious: is it connected to the incident? Three wrong calls and the checks are gone; right ones are free."
	else:
		mode_label.text = label
		mode_label.tooltip_text = "You judge everything yourself. (Absolute Beginner and Hobby Detective, chosen when starting a case, can check suspicious items.)"


func _set_mark(index: int, eid: String) -> void:
	if MARKS[index][1] == "":
		engine.clear_mark(eid)
	else:
		engine.mark(eid, MARKS[index][1])
	app.persist()


# =========================================================================== evidence
func _page_evidence() -> void:
	_title("Evidence", "What you found in town and copied from records. Record books stay where they are kept; go back to read them again.")
	var list := Kit.vbox(10)
	var conflicts := _conflict_map()
	var groups := [["trace", "Found in town"], ["record", "Copied from record books"],
			["observation", "Refusals and other observations"]]
	var any := false
	var hidden := 0
	for g in groups:
		var cards := []
		for e in engine.state["entries"]:
			if e["source"] != g[0]:
				continue
			if engine.status_of(String(e["id"])) == "ignored":
				hidden += 1
				continue
			cards.append(_entry_card(e, conflicts.get(e["id"], [])))
		if cards.is_empty():
			continue
		any = true
		list.add_child(Kit.label(g[1], "SubheadingLabel"))
		for c in cards:
			list.add_child(c)
	var read: Dictionary = engine.state["ui"]["read"]
	if not read.is_empty():
		any = true
		list.add_child(Kit.label("Record books you have asked for", "SubheadingLabel"))
		var keys: Array = read.keys()
		keys.sort()
		for k in keys:
			var bk: Dictionary = engine.data["records"][k]
			var row := Kit.hbox(10)
			row.add_child(Kit.label("%s  ·  kept at %s  ·  %s" % [bk["title"], engine.place_name(bk["place"]),
					"you may read it" if read[k]["allowed"] else "refused"]))
			var go := Kit.button("Go and read it" if read[k]["allowed"] else "Go there",
					"Close the tablet and walk to %s" % engine.place_name(bk["place"]), "TopicButton", "GoToBook_" + String(k))
			go.pressed.connect(Callable(screen, "route_to_book").bind(k))
			row.add_child(go)
			list.add_child(row)
	if hidden > 0:
		var row2 := Kit.flow()
		row2.add_child(Kit.label("%d item(s) you ignored are not shown." % hidden, "SmallLabel", false))
		var rv := Kit.button("Review ignored", "Reconsider what you set aside", "TopicButton", "GoToIgnored")
		rv.pressed.connect(review_ignored)
		row2.add_child(rv)
		list.add_child(row2)
	if not any and hidden == 0:
		list.add_child(Kit.label("Nothing yet. Look around the places in town, examine the vehicles, and ask to read the record books where they are kept.",
				"MutedLabel"))
	content.add_child(Kit.scroll(list))


# =========================================================================== people
func _page_people() -> void:
	_title("People", "Everyone in town. You can only question someone where they are; go and find them.")
	var split := Kit.hbox(14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := Kit.vbox(6)
	for r in engine.data["residents"]:
		var extra := ""
		if r["condition"] == "deceased":
			extra = "  ·  deceased"
		elif engine.state["ui"]["dialogue"].has(r["id"]):
			extra = "  ·  spoken to"
		var b := Kit.button("%s%s" % [r["name"], extra], "About %s" % r["first"], "NavButton", "Dir_" + String(r["id"]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if r["id"] == person:
			b.theme_type_variation = "NavButtonActive"
		b.pressed.connect(_pick_person_card.bind(r["id"]))
		list.add_child(b)
	var left := Kit.scroll(list)
	left.custom_minimum_size = Vector2(230, 0)
	left.size_flags_horizontal = Control.SIZE_FILL
	split.add_child(left)
	var right := Kit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if person == "":
		right.add_child(Kit.label("Choose someone to see what you know about them.", "MutedLabel"))
	else:
		_person_card(right)
	split.add_child(right)
	content.add_child(split)


func _pick_person_card(rid: String) -> void:
	person = rid
	show_page("people")


func _person_card(box: VBoxContainer) -> void:
	var r: Dictionary = engine.resident(person)
	var v := Kit.vbox(8)
	var top := Kit.hbox(12)
	top.add_child(Portrait.new().setup(r, 96.0, Expression.at_rest(r)))
	var nm := Kit.label(r["name"], "HeadingLabel")
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	v.add_child(top)
	v.add_child(Kit.label("%s, %s  ·  lives at %s" % [String(r["occupation"]).capitalize(), r["age_group"],
			engine.place_name(r["home"])], "MutedLabel"))
	if r["condition"] == "deceased":
		v.add_child(Kit.label("Deceased.", "DangerLabel"))
		var home := Kit.button("Go to %s" % engine.place_name(r["home"]), "Close the tablet and walk there", "TopicButton",
				"VisitHome_" + String(person))
		home.pressed.connect(Callable(screen, "route_to_place").bind(r["home"]))
		v.add_child(home)
	else:
		if r["condition"] == "injured":
			v.add_child(Kit.label("Injured.", "DangerLabel"))
		var seen = town.whereabouts(person)
		var where := "You saw %s at %s." % [r["first"], engine.place_name(seen)] if seen != null else \
				"You haven't seen %s today. You could try their home, %s." % [r["first"], engine.place_name(r["home"])]
		v.add_child(Kit.label(where, "AccentLabel"))
		var find := Kit.button("Go to %s" % r["first"], "Close the tablet and go to where %s is, or try their home" % r["first"],
				"PrimaryButton", "FindPerson_" + String(person))
		find.pressed.connect(Callable(screen, "find_person").bind(person))
		v.add_child(find)
	var history_log: Array = engine.state["ui"]["dialogue"].get(person, [])
	v.add_child(Kit.label("What they told you", "SubheadingLabel"))
	if history_log.is_empty():
		v.add_child(Kit.label("You have not spoken to them yet.", "MutedLabel"))
	for i in range(history_log.size() - 1, -1, -1):
		v.add_child(screen.exchange_card(history_log[i], r["first"]))
	box.add_child(Kit.scroll(v))


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
	var row := Kit.flow()
	row.add_child(Kit.label("Show:", "", false))
	var opt := Kit.option(opts, sel, "Follow one person")
	opt.name = "TimelinePerson"
	opt.item_selected.connect(_pick_timeline_person.bind(ids))
	row.add_child(opt)
	var real := _real(tl["contradictions"])
	row.add_child(Kit.label("%d thing(s) don't add up" % real.size(),
			"DangerLabel" if not real.is_empty() else "SmallLabel", false))
	var ignored := 0
	for e in tl["entries"]:
		if engine.status_of(String(e["id"])) == "ignored":
			ignored += 1
	if ignored > 0:
		var si := CheckBox.new()
		si.name = "ShowIgnored"
		si.text = "Show ignored (%d)" % ignored
		si.button_pressed = show_ignored
		si.toggled.connect(_toggle_show_ignored)
		row.add_child(si)
	# The timeline starts where people's first answers start; older entries stay one click away.
	var since: int = engine.recent_from()
	var older := 0
	for e in tl["entries"]:
		if int(e["time"]) < since:
			older += 1
	if older > 0:
		var se := CheckBox.new()
		se.name = "ShowEarlier"
		se.text = "Show earlier times (%d)" % older
		se.tooltip_text = "Entries from before %s" % Clock.fmt(since)
		se.button_pressed = show_earlier
		se.toggled.connect(_toggle_show_earlier)
		row.add_child(se)
	content.add_child(row)
	if (not show_ignored and ignored > 0) or (not show_earlier and older > 0):
		tl = tl.duplicate()
		var kept := []
		for f in tl["facts"]:
			if not show_ignored and engine.status_of(String(f["entry"])) == "ignored":
				continue
			if not show_earlier and int(f["to"]) < since:
				continue
			kept.append(f)
		tl["facts"] = kept
	if not tl["contradictions"].is_empty():
		content.add_child(_contradictions(tl["contradictions"]))
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
		if not show_ignored and engine.status_of(String(e["id"])) == "ignored":
			continue
		if not show_earlier and int(e["time"]) < since:
			continue
		var line := Kit.hbox(10)
		line.name = "Entry_" + String(e["id"])
		var stamp := Kit.label(("≈ " if e["id"].begins_with("S") else "") + e["label"], "AccentLabel", false)
		stamp.custom_minimum_size = Vector2(150, 0)
		stamp.tooltip_text = "Witness times are approximate." if e["id"].begins_with("S") else ""
		stamp.mouse_filter = Control.MOUSE_FILTER_STOP
		line.add_child(stamp)
		var body := Kit.vbox(2)
		body.add_child(Kit.label("[%s] %s" % [e["id"], e["text"]] + ("  (%s)" % e["mark"] if e["mark"] != null else "")))
		if not e["conflicts"].is_empty():
			body.add_child(Kit.label("⚠ Doesn't add up with " + ", ".join(PackedStringArray(e["conflicts"])), "DangerLabel"))
		body.add_child(_status_row(String(e["id"])))
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(body)
		list.add_child(line)
	if tl["entries"].is_empty():
		list.add_child(Kit.label("Nothing with a time on it yet. Ask people where they were and what they saw.",
				"MutedLabel"))
	elif list.get_child_count() == 0:
		list.add_child(Kit.label("Nothing to show here with these settings. Try showing earlier times or ignored entries.",
				"MutedLabel"))
	content.add_child(Kit.scroll(list))


## How each kind of contradiction is named and explained (mystery/investigate/contradictions.py).
const CONTRADICTION_TEXT := {
	"firm": ["Can't both be true", "Two first-hand accounts disagree. Someone is lying, or someone is mistaken.", "DangerLabel"],
	"document": ["A record says otherwise", "Written records are exact; people only remember times roughly. One of them is wrong.", "DangerLabel"],
	"uncertain": ["Unsure sighting", "It was dark and they weren't sure who they saw. Perhaps it was someone else.", "InfoLabel"],
	"secondhand": ["Secondhand account", "One of them is repeating what they were told. Stories change in the retelling.", "InfoLabel"],
	"approximate": ["Minor timing difference", "People's times are only approximate. This is probably not a contradiction at all.", "SmallLabel"],
}


static func _real(found: Array) -> Array:
	## Contradictions worth the name: everything but minor timing differences.
	var out := []
	for c in found:
		if c["kind"] != "approximate":
			out.append(c)
	return out


func _span_text(f: Dictionary) -> String:
	if int(f["from"]) == int(f["to"]):
		return "around %s" % Clock.fmt(f["from"])
	var a := Clock.fmt(f["from"])
	var b := Clock.fmt(f["to"])
	if a.substr(0, a.find(" ", 4)) == b.substr(0, b.find(" ", 4)):
		b = b.substr(b.find(" ", 4) + 1)
	return "from %s to %s" % [a, b]


func _contradictions(found: Array) -> Control:
	## Each disagreement in plain words: which two entries, where each puts the person, and when they clash.
	var box := Kit.vbox(8)
	box.name = "Contradictions"
	box.add_child(Kit.label("What doesn't add up", "PlaceTitle"))
	var minor := 0
	for i in range(found.size()):
		var c: Dictionary = found[i]
		if c["kind"] == "approximate":
			minor += 1
			if not show_minor:
				continue
		var txt: Array = CONTRADICTION_TEXT[c["kind"]]
		var card := Kit.panel("Card")
		card.name = "Contradiction_%d" % i
		var v := Kit.vbox(4)
		v.add_child(Kit.label("%s — %s" % [txt[0], _name(c["who"])], txt[2]))
		for side in [["a", "a_fact"], ["b", "b_fact"]]:
			var eid := String(c[side[0]])
			var e: Dictionary = engine.entry(eid)
			var f: Dictionary = c[side[1]]
			v.add_child(Kit.label("[%s] %s" % [eid, e.get("text", "")]))
			v.add_child(Kit.label("      puts %s at %s, %s" % [_name(c["who"]), engine.place_name(f["place"]), _span_text(f)],
					"SmallLabel"))
		var o: Array = c["overlap"]
		var clash := "around %s" % Clock.fmt(o[0]) if int(o[0]) == int(o[1]) else _span_text({"from": o[0], "to": o[1]})
		v.add_child(Kit.label("They clash %s: %d minutes into the other account. %s" % [clash, int(c["depth"]), txt[1]],
				"MutedLabel"))
		if c["entries"].size() > 2:
			v.add_child(Kit.label("Also involved: " + ", ".join(PackedStringArray(c["entries"])), "SmallLabel"))
		card.add_child(v)
		box.add_child(card)
	if minor > 0:
		var mb := CheckBox.new()
		mb.name = "ShowMinor"
		mb.text = "Show minor timing differences (%d)" % minor
		mb.tooltip_text = "Accounts that differ by no more than people's approximate times. Probably not contradictions."
		mb.button_pressed = show_minor
		mb.toggled.connect(_toggle_show_minor)
		box.add_child(mb)
	return box


func _toggle_show_minor(on: bool) -> void:
	show_minor = on
	show_page("timeline")


func _toggle_show_earlier(on: bool) -> void:
	show_earlier = on
	show_page("timeline")


func _toggle_show_ignored(on: bool) -> void:
	show_ignored = on
	show_page("timeline")


func _pick_timeline_person(index: int, ids: Array) -> void:
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
	var buttons := Kit.flow()
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
	box.add_child(Kit.label(label, "", false))
	opt.name = name_
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.clip_text = true
	box.add_child(opt)
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
	engine.state["ui"]["tablet"] = false
	var res: Dictionary = engine.reveal()
	app.show_reveal(res["model"])


# =========================================================================== hints
func _page_hints() -> void:
	_title("Hints", "Stuck? Hints point you at evidence you can reach. Each credit spent lowers your final score by 5 points.")
	var card := Kit.panel("Card")
	var v := Kit.vbox(8)
	v.add_child(Kit.label("Credits left: %d" % int(engine.state["credits"]), "AccentLabel"))
	var cost = engine.next_hint_cost()
	var b := Kit.button("Ask for a hint" if cost != null else "No more hints",
			"No more hints for this case." if cost == null else "The next hint costs %d credit(s)." % int(cost),
			"PrimaryButton", "HintButton")
	b.disabled = cost == null or int(engine.state["credits"]) < int(cost)
	b.pressed.connect(ask_hint)
	v.add_child(b)
	if cost != null:
		v.add_child(Kit.label("The next hint costs %d credit(s)." % int(cost), "SmallLabel"))
	card.add_child(v)
	content.add_child(card)
	var list := Kit.vbox(8)
	if engine.state["ui_hints"].is_empty():
		list.add_child(Kit.label("You have not bought any hints.", "MutedLabel"))
	for h in engine.state["ui_hints"]:
		list.add_child(_info_card(String(h["label"]), String(h["text"])))
	content.add_child(Kit.scroll(list))


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
	screen.refresh_credits()
	if res.get("ok", false):
		app.message(res["label"], res["text"])
	else:
		app.message("No hint", String(res.get("message", "")))
	if visible and page == "hints":
		show_page("hints")
	return res


# =========================================================================== case files
func _page_files() -> void:
	_title("Case files", "The investigations on this tablet. Only the open case can be worked on; the others stay locked until you return to the main menu.")
	var list := Kit.vbox(8)
	var active := Kit.panel("ActiveFile")
	active.name = "ActiveCaseFile"
	var av := Kit.vbox(4)
	av.add_child(Kit.label("OPEN  ·  " + String(engine.data["hook"]["title"]), "AccentLabel"))
	av.add_child(Kit.label("%s  ·  %s  ·  you are investigating this case" % [engine.data["town"], engine.data["start_label"]],
			"SmallLabel"))
	active.add_child(av)
	list.add_child(active)
	for e in app.library.entries:
		if e["case_id"] == engine.case_id:
			continue
		list.add_child(_locked_file(e))
	content.add_child(Kit.scroll(list))


func _locked_file(e: Dictionary) -> Control:
	## Shown, never openable: a disabled button with nothing connected to it.
	var b := Button.new()
	b.name = "CaseFile_" + String(e["case_id"])
	b.text = "LOCKED  ·  %s\n%s  ·  %s  ·  %s" % [e["title"], e["town"], e["season"], app._status_for(e["case_id"])]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Locked while another investigation is open. Return to the main menu to choose a different case."
	b.theme_type_variation = "NavButton"
	return b
