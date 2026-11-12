## The playable investigation rules: a faithful port of mystery/investigate/{dialogue,notebook,
## session}.py. Every public method returns the same structured result as the Python
## ``*_result`` methods (contract: docs/investigation-rules.md), which the parity tests compare.
##
## The truth is never touched here. ``reveal()`` delegates to verdict.gd, which unseals it only
## once the case has been concluded. No method prints anything.
extends RefCounted

const Clock = preload("res://scripts/core/clock.gd")
const Verdict = preload("res://scripts/core/verdict.gd")
const CaseFormat = preload("res://scripts/core/case_format.gd")

const BASE_TOPICS := [
	["whereabouts", "Where they were during the time in question"],
	["window", "What they saw or heard during that time"],
	["incident", "What they know about what happened"],
	["money", "Money troubles and debts around town"],
	["conflicts", "Arguments and grudges"],
	["rumors", "What people are saying"],
	["vehicles", "Vehicles and the road"],
	["past", "Other trouble in town lately"],
]
const NO_KNOWLEDGE := "I don't know anything about that."
const EVASIVE := {"nervous": "I... I'd rather not get into that.", "smooth": "Can't help you there, I'm afraid."}
const HESITATE := {"nervous": "(They hesitate, as if there is something more they are not saying.)", "smooth": ""}
const WORN_OUT := "That's enough questions for today. I've told you what I know."
const NOTHING_MORE := "(Pressing them doesn't get you anything more.)"
const NOTHING_LATELY := "Nothing lately that I know of."
const NOTHING_TO_ADD := "That's about all there is to it."
const NOTHING_EARLIER := "I can't think of anything before that."
## Follow-up questions: "tell me more" (the statements behind a summary) and "and before that?".
const FOLLOWS := ["more", "earlier"]
## Topics about this case or about the past are answered whatever the time.
const ALL_TIMES := ["incident", "past"]
const MARKS := ["confirmed", "disputed", "uncertain", "inference"]
const HINT_LABELS := {1: "Nudge", 2: "Lead", 3: "Strong hint"}
## Evidence management: one status per notebook entry. Ignoring hides, never deletes.
const STATUSES := ["suspicious", "active", "ignored"]
## Difficulty: Absolute Beginner and Hobby Detective may check what they marked suspicious, and get a
## Detective's intuition when two things they have found don't add up (the beginner is shown which two);
## Experienced Detective works it all out alone. Saves from before ("normal") play as Experienced.
const MODES := ["beginner", "hobby", "experienced"]
const MODE_LABELS := {"beginner": "Absolute Beginner", "hobby": "Hobby Detective", "experienced": "Experienced Detective"}
const MAX_STRIKES := 3
const CHECKABLE := ["statement", "trace", "record"]

var package: Dictionary
var data: Dictionary
var case_id: String
var state: Dictionary
var _items_by_key := {}
var _residents := {}


## Version of the saved state layout. A save from a newer build than this is refused (see SaveStore);
## older layouts are brought up to date in _normalize_state.
## 1: page-based interface.  2: town (ui.at/visited/seen) and tablet (ui.tablet, ui.tablet_page).
const STATE_VERSION := 2
const TABLET_PAGES := ["case", "notebook", "evidence", "people", "timeline", "theory", "hints", "files"]


## True when a saved investigation was resumed. save_mismatch is true when a save existed for this case id
## but was made for different case contents (for example, before the library was rebuilt), so it was not used.
var resumed := false
var save_mismatch := false


func _init(pkg: Dictionary, saved_state = null) -> void:
	package = pkg
	data = pkg["investigation"]
	case_id = pkg["case_id"]
	var fp := fingerprint(pkg)
	if typeof(saved_state) == TYPE_DICTIONARY and saved_state.get("case_id") == case_id:
		if String(saved_state.get("case_fingerprint", "")) == fp:
			state = saved_state
			resumed = true
		else:
			save_mismatch = true
	if not resumed:
		state = {"case_id": case_id, "credits": int(data["hint_credits"]), "hints_bought": 0, "concluded": false,
				"revealed": false, "theory": null}
	state["case_fingerprint"] = fp
	_normalize_state()
	for r in data["residents"]:
		_residents[r["id"]] = r
	for rid in data["testimony"]:
		for it in data["testimony"][rid]["items"]:
			_items_by_key[it["key"]] = it


static func fingerprint(pkg: Dictionary) -> String:
	## Identifies the exact contents of a case, so a save is never applied to a different version of it.
	var seal: Dictionary = pkg.get("sealed_truth", {})
	return (JSON.stringify(pkg["investigation"]) + "|" + String(seal.get("data_sha256", ""))).sha256_text()


func _normalize_state() -> void:
	## JSON gives back floats; the rules count in integers.
	for k in ["entries", "ui_hints"]:
		if not state.has(k):
			state[k] = []
	for k in ["counters", "by_ref", "goodwill", "pressed", "earlier", "ui"]:
		if typeof(state.get(k)) != TYPE_DICTIONARY:
			state[k] = {}
	for k in ["credits", "hints_bought", "hint_spend"]:
		state[k] = int(state.get(k, 0))
	for k in state["counters"].keys():
		state["counters"][k] = int(state["counters"][k])
	for k in state["goodwill"].keys():
		state["goodwill"][k] = int(state["goodwill"][k])
	for e in state["entries"]:
		if e.get("time") != null:
			e["time"] = int(e["time"])
	state["concluded"] = bool(state.get("concluded", false))
	state["revealed"] = bool(state.get("revealed", false))
	for k in ["status", "checks"]:
		if typeof(state.get(k)) != TYPE_DICTIONARY:
			state[k] = {}
	if String(state.get("mode", "")) == "normal":
		state["mode"] = "experienced"
	if not MODES.has(String(state.get("mode", ""))):
		state["mode"] = "experienced"
	if typeof(state.get("intuition")) != TYPE_DICTIONARY:
		state["intuition"] = {"seen": [], "pair": []}
	state["strikes"] = int(state.get("strikes", 0))
	if int(state.get("state_version", 1)) < 2:
		# v1 kept the open page of the old page-based interface; places and records now live in town.
		var old := String(state["ui"].get("page", "case"))
		state["ui"].erase("page")
		state["ui"]["tablet_page"] = old if TABLET_PAGES.has(old) else "case"
	if not TABLET_PAGES.has(String(state["ui"].get("tablet_page", ""))):
		state["ui"]["tablet_page"] = "case"
	state["state_version"] = STATE_VERSION


# --------------------------------------------------------------------------- lookups
func resident(rid: String) -> Dictionary:
	return _residents.get(rid, {})


func first_name(rid) -> String:
	if rid == null or not _residents.has(rid):
		return "no one" if rid == null else str(rid)
	return _residents[rid]["first"]


func place(pid: String) -> Dictionary:
	for p in data["places"]:
		if p["id"] == pid:
			return p
	return {}


func place_name(pid: String) -> String:
	var p := place(pid)
	return p["name"] if not p.is_empty() else pid


func vehicle(vid: String) -> Dictionary:
	for v in data["vehicles"]:
		if v["id"] == vid:
			return v
	return {}


func topics(rid: String) -> Array:
	## [[topic id, label], ...] - the eight base topics, then "About <person>" for everyone else.
	var out := []
	for t in BASE_TOPICS:
		out.append([t[0], t[1]])
	for r in data["residents"]:
		if r["id"] != rid:
			var label: String = "About " + r["first"]
			if r["condition"] == "deceased":
				label += " (deceased)"
			out.append(["person:" + r["id"], label])
	return out


func topic_label(rid: String, topic: String) -> String:
	for t in topics(rid):
		if t[0] == topic:
			return t[1]
	return topic


func item(key: String) -> Dictionary:
	return _items_by_key.get(key, {})


func is_closed() -> bool:
	return state["revealed"]


# --------------------------------------------------------------------------- notebook
func record(prefix: String, ref, text: String, source: String, time = null, speaker = null) -> String:
	if ref != null and state["by_ref"].has(ref):
		return state["by_ref"][ref]
	var n := int(state["counters"].get(prefix, 0)) + 1
	state["counters"][prefix] = n
	var eid := "%s%d" % [prefix, n]
	state["entries"].append({"id": eid, "ref": ref, "text": text, "source": source,
			"time": null if time == null else int(time), "speaker": speaker, "mark": null})
	if ref != null:
		state["by_ref"][ref] = eid
	return eid


func entry(eid: String) -> Dictionary:
	for e in state["entries"]:
		if String(e["id"]).to_lower() == eid.to_lower():
			return e
	return {}


func mark(eid: String, mark_name) -> bool:
	var e := entry(eid)
	if e.is_empty() or not MARKS.has(mark_name):
		return false
	e["mark"] = mark_name
	return true


func clear_mark(eid: String) -> void:
	var e := entry(eid)
	if not e.is_empty():
		e["mark"] = null


# --------------------------------------------------------------------------- evidence management
func status_of(eid: String) -> String:
	return String(state["status"].get(eid, ""))


func set_status(eid: String, status: String) -> bool:
	## "suspicious", "active" or "ignored"; "" clears it. The entry itself is never touched.
	if entry(eid).is_empty():
		return false
	if status == "":
		state["status"].erase(eid)
		return true
	if not STATUSES.has(status):
		return false
	state["status"][eid] = status
	return true


func mode() -> String:
	return String(state["mode"])


func can_check() -> bool:
	return mode() == "beginner" or mode() == "hobby"


func strikes_left() -> int:
	return maxi(0, MAX_STRIKES - int(state["strikes"]))


func checkable(eid: String) -> bool:
	## Could this entry be checked at all (ignoring strikes and its status)? A summary is not: its
	## statements are checked one by one.
	var e := entry(eid)
	return not e.is_empty() and CHECKABLE.has(String(e["source"])) and e["ref"] != null \
			and not is_summary(String(e["ref"]))


func recent_from() -> int:
	## Where people's first answers start; anything before it comes up when you ask "and before that?".
	var hook: Dictionary = data["hook"]
	if hook.has("recent_from"):
		return int(hook["recent_from"])
	return int(hook["window"][0]) - 13 * 60


func is_summary(ref: String) -> bool:
	## A statement that sums up others ("I saw A, B and C at the pub ...") rather than saying one thing.
	## (A plain account of someone's whereabouts also has the exact account behind it, but it is a
	## statement in its own right, with its own verdict.)
	var it := item(ref)
	if it.get("members", []).is_empty():
		return false
	var rel = package.get("relevance", {})
	return typeof(rel) != TYPE_DICTIONARY or not rel.get("items", {}).has(ref)


func check(eid: String) -> Dictionary:
	## Hobby Detective: is this suspicious item connected to the incident? Opens only this item's
	## sealed verdict (never the truth). Unrelated costs a strike; connected and uncertain are free;
	## asking again about the same item gives the same answer for free.
	if state["concluded"]:
		return {"op": "check", "error": "closed"}
	if not can_check():
		return {"op": "check", "error": "Checks are for Absolute Beginners and Hobby Detectives."}
	if not checkable(eid):
		var e := entry(eid)
		if not e.is_empty() and e["ref"] != null and is_summary(String(e["ref"])):
			return {"op": "check", "error": "That sums up several statements. Ask them to tell you more, then check the statements one by one."}
		return {"op": "check", "error": "Only statements, evidence and records can be checked."}
	if state["checks"].has(eid):
		var prev: Dictionary = state["checks"][eid]
		return {"op": "check", "entry": eid, "verdict": prev["verdict"], "reason": prev["reason"], "strike": false,
				"strikes": int(state["strikes"]), "left": strikes_left(), "repeat": true}
	if status_of(eid) != "suspicious":
		return {"op": "check", "error": "Mark it suspicious first."}
	if strikes_left() == 0:
		return {"op": "check", "error": "You have no checks left: three of your judgements were wrong."}
	var opened: String = CaseFormat.open_relevance(package, String(entry(eid)["ref"]))
	var parts := opened.split("|")
	if parts.size() != 2 or not ["connected", "unrelated", "uncertain"].has(parts[0]):
		return {"op": "check", "error": "This case file has nothing to check this against."}
	var strike: bool = parts[0] == "unrelated"
	if strike:
		state["strikes"] = int(state["strikes"]) + 1
	state["checks"][eid] = {"verdict": parts[0], "reason": parts[1]}
	return {"op": "check", "entry": eid, "verdict": parts[0], "reason": parts[1], "strike": strike,
			"strikes": int(state["strikes"]), "left": strikes_left(), "repeat": false}


func note(text: String, time = null) -> String:
	return record("N", null, text, "note", time)


# --------------------------------------------------------------------------- questioning
func ask(rid: String, topic: String, press := false, follow := "") -> Dictionary:
	## follow: "" for the question itself, "more" for "tell me more", "earlier" for "and before that?".
	if is_closed():
		return {"op": "ask", "error": "closed"}
	var r := resident(rid)
	if r.is_empty():
		return {"op": "ask", "error": "No resident %s." % rid}
	if (follow != "" and not FOLLOWS.has(follow)) or (follow != "" and press):
		return {"op": "ask", "error": "Unknown follow-up %s." % follow}
	var res := {"op": "ask", "speaker": rid, "topic": topic, "pressed": press, "follow": follow, "dead": false,
			"lines": [], "goodwill": null, "can_press": false, "can_more": false, "can_earlier": false,
			"followups": []}
	if r["condition"] == "deceased":
		res["dead"] = true
		res["lines"] = [{"text": "%s is dead." % r["first"], "notes": []}]
		return res
	var valid := false
	for t in topics(rid):
		if t[0] == topic:
			valid = true
	if not valid:
		return {"op": "ask", "error": "Unknown topic %s." % topic}
	var followups := []
	for line in _answer(rid, topic, press, follow):
		var ids := []
		for it in line[1]:
			ids.append(record("S", it["key"], "%s: \"%s\"" % [r["first"], it["text"]], "statement", it["time"], rid))
			for x in it["about"]:
				if x != rid and not followups.has(x):
					followups.append(x)
		res["lines"].append({"text": line[0], "notes": ids})
	res["goodwill"] = int(state["goodwill"][rid])
	res["can_press"] = not state["pressed"][rid].has(topic) and int(state["goodwill"][rid]) > 0
	res.merge(follow_ups(rid, topic), true)
	followups.sort()
	res["followups"] = followups
	return res


func _answer(rid: String, topic: String, press: bool, follow: String) -> Array:
	## [[text, [items behind it]], ...] - dialogue.answer() in Python.
	var t = data["testimony"].get(rid)
	if t == null:
		return [["They cannot be questioned.", []]]
	if not state["goodwill"].has(rid):
		state["goodwill"][rid] = int(t["goodwill"])
	if not state["pressed"].has(rid):
		state["pressed"][rid] = []
	if not state["earlier"].has(rid):
		state["earlier"][rid] = []
	var pressed: Array = state["pressed"][rid]
	if press:
		if pressed.has(topic):
			return [["You've already pushed them on that.", []]]
		if int(state["goodwill"][rid]) <= 0:
			return [[WORN_OUT, []]]
		state["goodwill"][rid] = int(state["goodwill"][rid]) - 1
		pressed.append(topic)
	var earlier: Array = state["earlier"][rid]
	if follow == "earlier" and not earlier.has(topic) and not ALL_TIMES.has(topic):
		earlier.append(topic)
	var view := view_of(rid, topic)
	var allow_guarded := pressed.has(topic)
	var shown := []
	var hidden := []
	if follow == "more":
		for it in view["behind"]:
			if not state["by_ref"].has(it["key"]):
				shown.append(it)
	else:
		var era := "earlier" if follow == "earlier" and not ALL_TIMES.has(topic) else "recent"
		for it in view["front"]:
			if not ALL_TIMES.has(topic) and _era(it) != era:
				continue
			if allow_guarded or not it["guarded"]:
				shown.append(it)
			else:
				hidden.append(it)
	shown.sort_custom(_item_before)
	var lines := []
	if shown.is_empty():
		if follow == "more":
			lines.append([NOTHING_TO_ADD, []])
		elif follow == "earlier":
			lines.append([EVASIVE[t["style"]] if not hidden.is_empty() else NOTHING_EARLIER, []])
		elif t["evasive_topics"].has(topic) or not hidden.is_empty():
			lines.append([EVASIVE[t["style"]], []])
		elif not view["earlier"].is_empty():
			lines.append([NOTHING_LATELY, []])
		else:
			lines.append([NO_KNOWLEDGE, []])
	for g in _group(shown):
		lines.append(g)
	if not hidden.is_empty() and HESITATE[t["style"]] != "":
		lines.append([HESITATE[t["style"]], []])
	if press and allow_guarded:
		var any_guarded := false
		for it in t["items"]:
			if it["topics"].has(topic) and it["guarded"]:
				any_guarded = true
		if not any_guarded:
			lines.append([NOTHING_MORE, []])
	return lines


static func _era(it) -> String:
	return String(it.get("era", "recent"))


func view_of(rid: String, topic: String) -> Dictionary:
	## What this person could tell on a topic right now: the statements in front (told when asked), those
	## behind summaries already within reach, and the ones further back (dialogue.view_of in Python).
	var t = data["testimony"].get(rid)
	var out := {"front": [], "behind": [], "earlier": []}
	if t == null:
		return out
	var summaries := {}
	for it in t["items"]:
		if not it.get("members", []).is_empty():
			summaries[it["key"]] = it
	var pressed: Array = state["pressed"].get(rid, [])
	var all_times: bool = ALL_TIMES.has(topic)
	var reach_earlier: bool = all_times or state["earlier"].get(rid, []).has(topic)
	for it in t["items"]:
		if not it["topics"].has(topic):
			continue
		var s = summaries.get(it.get("in", ""))
		if s != null and s["topics"].has(topic):
			if _era(s) == "recent" or reach_earlier:
				out["behind"].append(it)
			continue
		out["front"].append(it)
		if not all_times and _era(it) == "earlier" and (pressed.has(topic) or not it["guarded"]):
			out["earlier"].append(it)
	return out


func follow_ups(rid: String, topic: String) -> Dictionary:
	## Which follow-up questions would get anything new (dialogue.follow_ups in Python).
	var view := view_of(rid, topic)
	var can_more := false
	for it in view["behind"]:
		if not state["by_ref"].has(it["key"]):
			can_more = true
	var asked_earlier: bool = state["earlier"].get(rid, []).has(topic)
	return {"can_more": can_more, "can_earlier": not view["earlier"].is_empty() and not asked_earlier}


func _item_before(a, b) -> bool:
	## Python: sort by (time is None, time or 0, key).
	var an: bool = a["time"] == null
	var bn: bool = b["time"] == null
	if an != bn:
		return not an
	var at := 0 if an else int(a["time"])
	var bt := 0 if bn else int(b["time"])
	if at != bt:
		return at < bt
	return String(a["key"]) < String(b["key"])


func _has_group(it) -> bool:
	return it.has("group") and typeof(it["group"]) == TYPE_DICTIONARY and not it["group"].is_empty()


func _group(items: Array) -> Array:
	## Merge "I saw A at X" + "I saw B at X" into one sentence; every item stays in the notebook.
	var groups := {}
	var order := []
	for it in items:
		var gid = null
		if _has_group(it):
			gid = it["group"].get("id")
		var key = gid if gid else it["key"]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		groups[key].append(it)
	var out := []
	for key in order:
		var members: Array = groups[key]
		if members.size() == 1 or not _has_group(members[0]):
			for m in members:
				out.append([m["text"], [m]])
			continue
		var names := PackedStringArray()
		for m in members:
			if not names.has(m["group"]["name"]):
				names.append(m["group"]["name"])
		var joined := names[0]
		if names.size() > 1:
			joined = ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]
		out.append([String(members[0]["group"]["template"]).replace("{names}", joined), members])
	return out


# --------------------------------------------------------------------------- looking around
func inspect_place(pid: String) -> Dictionary:
	if is_closed():
		return {"op": "inspect_place", "error": "closed"}
	var p := place(pid)
	if p.is_empty():
		return {"op": "inspect_place", "error": "No place %s." % pid}
	var res := {"op": "inspect_place", "id": p["id"], "name": p["name"], "allowed": p["allowed"], "reply": p["reply"],
			"show_reply": p["reply"] != "" and not p["owners"].is_empty(), "traces": [], "books": [],
			"vehicles": [], "note": null}
	if not p["allowed"]:
		res["show_reply"] = true
		res["note"] = record("O", "refused:" + p["id"], "Refused entry to %s. %s" % [p["name"], p["reply"]],
				"observation")
		return res
	for tr in p["traces"]:
		var eid := record("X", tr["id"], "At %s: %s" % [p["name"], tr["description"]], "trace")
		res["traces"].append({"id": tr["id"], "description": tr["description"], "note": eid})
	for k in data["records"]:
		if data["records"][k]["place"] == p["id"]:
			res["books"].append(k)
	for v in data["vehicles"]:
		if v["location"] == p["id"]:
			res["vehicles"].append(v["id"])
	return res


func inspect_vehicle(vid: String) -> Dictionary:
	if is_closed():
		return {"op": "inspect_vehicle", "error": "closed"}
	var v := vehicle(vid)
	if v.is_empty():
		return {"op": "inspect_vehicle", "error": "No vehicle %s." % vid}
	var res := {"op": "inspect_vehicle", "id": v["id"], "name": v["name"], "location": v["location"],
			"allowed": v["allowed"], "reply": v["reply"], "traces": [], "note": null}
	if not v["allowed"]:
		res["note"] = record("O", "refused:" + v["id"], "Not allowed to look at %s. %s" % [v["name"], v["reply"]],
				"observation")
		return res
	for tr in v["traces"]:
		var eid := record("X", tr["id"], tr["description"], "trace")
		res["traces"].append({"id": tr["id"], "description": tr["description"], "note": eid})
	return res


func read(book: String, day = null) -> Dictionary:
	if is_closed():
		return {"op": "read", "error": "closed"}
	if not data["records"].has(book):
		return {"op": "read", "error": "No record book %s." % book}
	var b = data["records"][book]
	var res := {"op": "read", "book": book, "title": b["title"], "allowed": b["allowed"], "reply": b["reply"],
			"day": day, "entries": [], "note": null}
	if not b["allowed"]:
		res["note"] = record("O", "refused:" + book, "Not allowed to read the %s. %s" % [b["title"], b["reply"]],
				"observation")
		return res
	for e in b["entries"]:
		if day == null or Clock.day_of(e["time"]) == int(day):
			res["entries"].append({"id": e["id"], "time": int(e["time"]), "text": e["text"]})
	var label: String = "Read the " + b["title"]
	if day != null and int(day) != 0:
		label += " for Day %d" % int(day)
	res["note"] = record("O", "read:%s:%s" % [book, "None" if day == null else str(int(day))], label, "observation")
	return res


func record_entry(ref: String) -> Dictionary:
	for key in data["records"]:
		var b = data["records"][key]
		if not b["allowed"]:
			continue
		for e in b["entries"]:
			var id: String = e["id"]
			if id.substr(2).to_lower() == ref.to_lower() or id.to_lower() == ref.to_lower():
				return e
	return {}


func cite_record(ref: String):
	## Copy a record line into the notebook. Returns the entry id or null.
	var e := record_entry(ref)
	if e.is_empty():
		return null
	return record("D", e["id"], e["text"], "record", e["time"])


# --------------------------------------------------------------------------- hints
func hint() -> Dictionary:
	if is_closed():
		return {"op": "hint", "error": "closed"}
	var hints: Array = data["hints"]
	var n := int(state["hints_bought"])
	var res := {"op": "hint", "ok": false, "tier": null, "label": null, "cost": null, "text": null,
			"credits": int(state["credits"]), "message": null}
	if n >= hints.size():
		res["message"] = "There are no more hints for this case."
		return res
	var h = hints[n]
	var cost := int(h["cost"])
	if int(state["credits"]) < cost:
		res["message"] = "The next hint costs %d credits; you have %d." % [cost, int(state["credits"])]
		return res
	state["credits"] = int(state["credits"]) - cost
	state["hints_bought"] = n + 1
	state["hint_spend"] = int(state.get("hint_spend", 0)) + cost
	res["ok"] = true
	res["tier"] = int(h["tier"])
	res["label"] = HINT_LABELS.get(int(h["tier"]), "Hint")
	res["cost"] = cost
	res["text"] = h["text"]
	res["credits"] = int(state["credits"])
	state["ui_hints"].append({"label": res["label"], "cost": cost, "text": h["text"]})
	return res


func next_hint_cost():
	var n := int(state["hints_bought"])
	if n >= data["hints"].size():
		return null
	return int(data["hints"][n]["cost"])


# --------------------------------------------------------------------------- timeline
func entry_less(a: String, b: String) -> bool:
	## Python _entry_order: (prefix letter, number).
	if a.substr(0, 1) != b.substr(0, 1):
		return a.substr(0, 1) < b.substr(0, 1)
	return a.substr(1).to_int() < b.substr(1).to_int()


func _timed_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a["time"]) != int(b["time"]):
		return int(a["time"]) < int(b["time"])
	return String(a["id"]) < String(b["id"])


# --------------------------------------------------------------------------- detective's intuition
## When the player leaves a conversation or a place: a new disagreement worth the name - two first-hand
## accounts, or a record against a statement, about the time in question - between entries already in the
## notebook. Worked out from the notebook alone, like the timeline: never from the sealed truth, and never
## pointing at a person. Each disagreement is told once, one at a time; Experienced Detectives get none.
const INTUITION_KINDS := ["firm", "document"]


func intuition() -> Dictionary:
	## {} or {"a", "b", "who", "kind"}; remembered, so the same disagreement never comes up again.
	if state["concluded"] or mode() == "experienced":
		return {}
	var seen: Array = state["intuition"]["seen"]
	var since := recent_from()
	for c in timeline()["contradictions"]:
		if not INTUITION_KINDS.has(c["kind"]) or int(c["overlap"][1]) < since:
			continue
		var told := false
		for p in c["pairs"]:
			if seen.has("%s|%s" % [p[0], p[1]]):
				told = true
		if told:
			continue
		for p in c["pairs"]:
			seen.append("%s|%s" % [p[0], p[1]])
		state["intuition"]["pair"] = [c["a"], c["b"]]
		return {"a": c["a"], "b": c["b"], "who": c["who"], "kind": c["kind"]}
	return {}


# --------------------------------------------------------------------------- contradictions
## mystery/investigate/contradictions.py: clashes between notebook entries, grouped and classified by what
## the player can see. firm (two first-hand accounts that cannot both be right), document (a record against
## a statement), uncertain (one of them was not sure who they saw), secondhand (one of them was told), or
## approximate (no bigger than the "about" in people's times: a minor note, never a conflict).
const C_MARGIN := 20
const C_APPROX := 60
const C_DOCUMENT := 30
const C_NEAR := 30
const KIND_RANK := {"firm": 4, "document": 3, "secondhand": 2, "uncertain": 1, "approximate": 0}


static func clash(a: Dictionary, b: Dictionary) -> Array:
	## [depth, overlap start, overlap end] if two facts put one person in two places at once, else [].
	var af := int(a["from"])
	var at := int(a["to"])
	var bf := int(b["from"])
	var bt := int(b["to"])
	if af == at and bf == bt:
		return [0, af, af] if af == bf else []
	if af == at or bf == bt:
		var m := af if af == at else bf
		var sf := bf if af == at else af
		var st := bt if af == at else at
		if sf + C_MARGIN < m and m < st - C_MARGIN:
			return [mini(m - sf, st - m), m, m]
		return []
	var lo := maxi(af, bf)
	var hi := mini(at, bt)
	if hi - lo > 2 * C_MARGIN:
		return [hi - lo, lo, hi]
	return []


static func kind_of(a: Dictionary, b: Dictionary, ia: Dictionary, ib: Dictionary, depth: int) -> String:
	if ia["kind"] == "record" or ib["kind"] == "record":
		return "document" if depth > C_DOCUMENT else "approximate"
	if bool(a.get("hedged", false)) or bool(b.get("hedged", false)):
		return "uncertain"
	if ia["source"] == "told" or ib["source"] == "told":
		return "secondhand"
	return "firm" if depth > C_APPROX else "approximate"


func _raw_less(p: Dictionary, q: Dictionary) -> bool:
	## Python: (who, places, lo, hi, entry order of a, entry order of b).
	if p["who"] != q["who"]:
		return String(p["who"]) < String(q["who"])
	for i in range(2):
		if p["places"][i] != q["places"][i]:
			return String(p["places"][i]) < String(q["places"][i])
	if int(p["lo"]) != int(q["lo"]):
		return int(p["lo"]) < int(q["lo"])
	if int(p["hi"]) != int(q["hi"]):
		return int(p["hi"]) < int(q["hi"])
	if p["a"] != q["a"]:
		return entry_less(p["a"], q["a"])
	return entry_less(p["b"], q["b"])


func _found_less(p: Dictionary, q: Dictionary) -> bool:
	## Python: (overlap start, who, entry order of a, entry order of b).
	if int(p["overlap"][0]) != int(q["overlap"][0]):
		return int(p["overlap"][0]) < int(q["overlap"][0])
	if p["who"] != q["who"]:
		return String(p["who"]) < String(q["who"])
	if p["a"] != q["a"]:
		return entry_less(p["a"], q["a"])
	return entry_less(p["b"], q["b"])


static func _strength(r: Dictionary, info: Dictionary) -> Array:
	var plain := (0 if info[r["a"]]["summary"] else 1) + (0 if info[r["b"]]["summary"] else 1)
	return [KIND_RANK[r["kind"]], plain, int(r["depth"])]


static func _stronger(p: Array, q: Array) -> bool:
	for i in range(p.size()):
		if p[i] != q[i]:
			return p[i] > q[i]
	return false


static func _span(f: Dictionary) -> Dictionary:
	return {"place": f["place"], "from": int(f["from"]), "to": int(f["to"])}


func contradictions(facts: Array, info: Dictionary) -> Array:
	var raw := []
	for i in range(facts.size()):
		var a: Dictionary = facts[i]
		for j in range(i + 1, facts.size()):
			var b: Dictionary = facts[j]
			if a["who"] != b["who"] or a["place"] == b["place"] or a["entry"] == b["entry"]:
				continue
			var c := clash(a, b)
			if c.is_empty():
				continue
			var x := a
			var y := b
			if entry_less(String(b["entry"]), String(a["entry"])):
				x = b
				y = a
			var places := [String(x["place"]), String(y["place"])]
			if places[1] < places[0]:
				places = [places[1], places[0]]
			raw.append({"who": a["who"], "places": places, "a": x["entry"], "b": y["entry"], "fa": x, "fb": y,
					"depth": int(c[0]), "lo": int(c[1]), "hi": int(c[2]),
					"kind": kind_of(x, y, info[x["entry"]], info[y["entry"]], int(c[0]))})
	raw.sort_custom(_raw_less)
	var groups := []
	for r in raw:
		var home = null
		for g in groups:
			if g["who"] == r["who"] and g["places"] == r["places"] and int(r["lo"]) <= int(g["hi"]) + C_NEAR \
					and int(g["lo"]) <= int(r["hi"]) + C_NEAR:
				home = g
				break
		if home == null:
			groups.append({"who": r["who"], "places": r["places"], "lo": r["lo"], "hi": r["hi"], "pairs": [r]})
		else:
			home["lo"] = mini(int(home["lo"]), int(r["lo"]))
			home["hi"] = maxi(int(home["hi"]), int(r["hi"]))
			home["pairs"].append(r)
	var out := []
	for g in groups:
		var best: Dictionary = g["pairs"][0]
		for k in range(1, g["pairs"].size()):
			var r: Dictionary = g["pairs"][k]
			if _stronger(_strength(r, info), _strength(best, info)):
				best = r
		var seen := {}
		var entries := []
		var pairs := []
		for r in g["pairs"]:
			for e in [r["a"], r["b"]]:
				if not seen.has(e):
					seen[e] = true
					entries.append(e)
			pairs.append([r["a"], r["b"], r["kind"]])
		entries.sort_custom(entry_less)
		out.append({"who": g["who"], "kind": best["kind"], "a": best["a"], "b": best["b"],
				"a_fact": _span(best["fa"]), "b_fact": _span(best["fb"]), "overlap": [int(best["lo"]), int(best["hi"])],
				"depth": int(best["depth"]), "entries": entries, "pairs": pairs})
	out.sort_custom(_found_less)
	return out


func timeline() -> Dictionary:
	var timed := []
	for e in state["entries"]:
		if e["time"] != null:
			timed.append(e)
	timed.sort_custom(_timed_less)
	var facts := []
	var info := {}
	for e in state["entries"]:
		var src := {}
		if e["source"] == "statement" and e.get("ref") != null:
			src = item(String(e["ref"]))
			info[e["id"]] = {"kind": "statement", "source": String(src.get("source", "")),
					"summary": src.get("members", []).size() >= 2}
		elif e["source"] == "record" and e.get("ref") != null:
			src = record_entry(String(e["ref"]))
			info[e["id"]] = {"kind": "record", "source": "record", "summary": false}
		for f in src.get("facts", []):
			facts.append({"entry": e["id"], "who": f["who"], "place": f["place"], "from": int(f["from"]),
					"to": int(f["to"]), "hedged": f.get("hedged", false)})
	var found := contradictions(facts, info)
	var partner := {}
	for c in found:
		for p in c["pairs"]:
			if p[2] == "approximate":
				continue
			for pair in [[p[0], p[1]], [p[1], p[0]]]:
				if not partner.has(pair[0]):
					partner[pair[0]] = []
				if not partner[pair[0]].has(pair[1]):
					partner[pair[0]].append(pair[1])
	var entries := []
	for e in timed:
		var others: Array = partner.get(e["id"], []).duplicate()
		others.sort_custom(entry_less)
		entries.append({"id": e["id"], "time": int(e["time"]), "label": Clock.fmt(e["time"]), "text": e["text"],
				"mark": e["mark"], "conflicts": others})
	return {"entries": entries, "facts": facts, "contradictions": found}


# --------------------------------------------------------------------------- conclusion
func mechanisms() -> Array:
	return data["theory_options"]["mechanisms"]


func motives() -> Array:
	return data["theory_options"]["motives"]


func submit(mechanism: String, responsible, motive: String, cites: Array, summary: String) -> Dictionary:
	if is_closed():
		return {"op": "submit", "error": "closed"}
	if state["concluded"]:
		return {"op": "submit", "error": "You have already concluded this case."}
	var ok_mech := false
	for m in mechanisms():
		if m["id"] == mechanism:
			ok_mech = true
	if not ok_mech:
		return {"op": "submit", "error": "Unknown explanation %s." % mechanism}
	var ok_motive := false
	for m in motives():
		if m["id"] == motive:
			ok_motive = true
	if not ok_motive:
		return {"op": "submit", "error": "Unknown motive %s." % motive}
	var rid = null
	if responsible != null and not ["", "none", "no one", "nobody", "-"].has(String(responsible).to_lower()):
		if resident(responsible).is_empty():
			return {"op": "submit", "error": "No single resident matches %s." % responsible}
		rid = responsible
	var refs := []
	for c in cites:
		var e := entry(c)
		if e.is_empty():
			var id = cite_record(c)
			if id == null:
				return {"op": "submit", "error": "%s is not in your notebook or an open record book." % c}
			e = entry(id)
		refs.append(e["id"])
	state["theory"] = {"mechanism": mechanism, "responsible": rid, "motive": motive, "cites": refs, "summary": summary}
	state["concluded"] = true
	return {"op": "submit", "ok": true, "mechanism": mechanism, "responsible": rid, "motive": motive, "cites": refs}


func give_up() -> Dictionary:
	if is_closed():
		return {"op": "giveup", "error": "closed"}
	state["concluded"] = true
	state["theory"] = null
	return {"op": "giveup", "ok": true}


func reveal() -> Dictionary:
	## {"op": "reveal", "sealed": true, "model": null} until the case is concluded.
	return Verdict.reveal(self)
