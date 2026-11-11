## The playable investigation rules: a faithful port of mystery/investigate/{dialogue,notebook,
## session}.py. Every public method returns the same structured result as the Python
## ``*_result`` methods (contract: docs/investigation-rules.md), which the parity tests compare.
##
## The truth is never touched here. ``reveal()`` delegates to verdict.gd, which unseals it only
## once the case has been concluded. No method prints anything.
extends RefCounted

const Clock = preload("res://scripts/core/clock.gd")
const Verdict = preload("res://scripts/core/verdict.gd")

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
const MARKS := ["confirmed", "disputed", "uncertain", "inference"]
const CONFLICT_MARGIN := 20
const HINT_LABELS := {1: "Nudge", 2: "Lead", 3: "Strong hint"}

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
	for k in ["counters", "by_ref", "goodwill", "pressed", "ui"]:
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


func note(text: String, time = null) -> String:
	return record("N", null, text, "note", time)


# --------------------------------------------------------------------------- questioning
func ask(rid: String, topic: String, press := false) -> Dictionary:
	if is_closed():
		return {"op": "ask", "error": "closed"}
	var r := resident(rid)
	if r.is_empty():
		return {"op": "ask", "error": "No resident %s." % rid}
	var res := {"op": "ask", "speaker": rid, "topic": topic, "pressed": press, "dead": false, "lines": [],
			"goodwill": null, "can_press": false, "followups": []}
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
	for line in _answer(rid, topic, press):
		var ids := []
		for it in line[1]:
			ids.append(record("S", it["key"], "%s: \"%s\"" % [r["first"], it["text"]], "statement", it["time"], rid))
			for x in it["about"]:
				if x != rid and not followups.has(x):
					followups.append(x)
		res["lines"].append({"text": line[0], "notes": ids})
	res["goodwill"] = int(state["goodwill"][rid])
	res["can_press"] = not state["pressed"][rid].has(topic) and int(state["goodwill"][rid]) > 0
	followups.sort()
	res["followups"] = followups
	return res


func _answer(rid: String, topic: String, press: bool) -> Array:
	## [[text, [items behind it]], ...] - dialogue.answer() in Python.
	var t = data["testimony"].get(rid)
	if t == null:
		return [["They cannot be questioned.", []]]
	if not state["goodwill"].has(rid):
		state["goodwill"][rid] = int(t["goodwill"])
	if not state["pressed"].has(rid):
		state["pressed"][rid] = []
	var pressed: Array = state["pressed"][rid]
	if press:
		if pressed.has(topic):
			return [["You've already pushed them on that.", []]]
		if int(state["goodwill"][rid]) <= 0:
			return [[WORN_OUT, []]]
		state["goodwill"][rid] = int(state["goodwill"][rid]) - 1
		pressed.append(topic)
	var allow_guarded := pressed.has(topic)
	var items := []
	for it in t["items"]:
		if it["topics"].has(topic):
			items.append(it)
	var shown := []
	var hidden := []
	for it in items:
		if allow_guarded or not it["guarded"]:
			shown.append(it)
		elif it["guarded"]:
			hidden.append(it)
	shown.sort_custom(_item_before)
	var lines := []
	if shown.is_empty():
		if t["evasive_topics"].has(topic) or not hidden.is_empty():
			lines.append([EVASIVE[t["style"]], []])
		else:
			lines.append([NO_KNOWLEDGE, []])
	for g in _group(shown):
		lines.append(g)
	if not hidden.is_empty() and HESITATE[t["style"]] != "":
		lines.append([HESITATE[t["style"]], []])
	if press and hidden.is_empty() and allow_guarded:
		var any_guarded := false
		for it in items:
			if it["guarded"]:
				any_guarded = true
		if not any_guarded:
			lines.append([NOTHING_MORE, []])
	return lines


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


func _conflict_less(p: Array, q: Array) -> bool:
	if p[0] != q[0]:
		return entry_less(p[0], q[0])
	if p[1] != q[1]:
		return entry_less(p[1], q[1])
	return String(p[2]) < String(q[2])


func _timed_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a["time"]) != int(b["time"]):
		return int(a["time"]) < int(b["time"])
	return String(a["id"]) < String(b["id"])


func find_conflicts(facts: Array) -> Array:
	## Pairs of entries that put the same person in two places at once (find_conflicts in Python).
	var out := []
	var seen := {}
	for i in range(facts.size()):
		var a = facts[i]
		for j in range(i + 1, facts.size()):
			var b = facts[j]
			if a["who"] != b["who"] or a["place"] == b["place"] or a["entry"] == b["entry"]:
				continue
			var af := int(a["from"])
			var at := int(a["to"])
			var bf := int(b["from"])
			var bt := int(b["to"])
			var clash := false
			if af == at and bf == bt:
				clash = af == bf
			elif af == at:
				clash = bf + CONFLICT_MARGIN < af and af < bt - CONFLICT_MARGIN
			elif bf == bt:
				clash = af + CONFLICT_MARGIN < bf and bf < at - CONFLICT_MARGIN
			else:
				clash = mini(at, bt) - maxi(af, bf) > 2 * CONFLICT_MARGIN
			if clash:
				var x: String = a["entry"]
				var y: String = b["entry"]
				if entry_less(y, x):
					var tmp := x
					x = y
					y = tmp
				var key := "%s|%s|%s" % [x, y, a["who"]]
				if not seen.has(key):
					seen[key] = true
					out.append([x, y, a["who"]])
	out.sort_custom(_conflict_less)
	return out


func timeline() -> Dictionary:
	var timed := []
	for e in state["entries"]:
		if e["time"] != null:
			timed.append(e)
	timed.sort_custom(_timed_less)
	var facts := []
	for e in state["entries"]:
		if e["source"] == "statement" and e.get("ref") != null:
			var it := item(e["ref"])
			for f in it.get("facts", []):
				facts.append({"entry": e["id"], "who": f["who"], "place": f["place"], "from": int(f["from"]),
						"to": int(f["to"]), "hedged": f.get("hedged", false)})
	var conflicts := find_conflicts(facts)
	var partner := {}
	for c in conflicts:
		for pair in [[c[0], c[1]], [c[1], c[0]]]:
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
	return {"entries": entries, "facts": facts, "conflicts": conflicts}


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
