## The truth-blind investigator: the solvability gate of case generation (Pilot 4B).
##
## It plays a case the way a careful player can, through the real investigation engine (core/investigation.gd) and
## nothing else, on a copy of the package that holds only the player's view: no sealed truth, no relevance verdicts,
## no summary or generator metadata. It asks everyone about everything (presses where people hesitate or dodge, as
## far as their patience goes, then asks for more and for earlier), looks at every place and vehicle it may, reads
## every book it may and copies its lines into the notebook. Then it reasons from the notebook alone - the
## statements, traces and record lines it was given, and the contradictions the player's own timeline shows - and
## either submits a theory with the entries it rests on, or says why it cannot.
##
## Lines of reasoning (each needs one chain, never a count of channels):
##   theft      someone's own account of the time in question is proven false - by a record, by another first-hand
##              statement of their own, or by two independent eyewitnesses (one witness against one account is word
##              against word) - and that person alone; the motive is the money trouble, or failing that the grudge
##              against the household robbed, that people describe.
##   assault    someone who was there - the victim, or an eyewitness - names the attacker, and nobody who was there
##              names anyone else; drink, a quarrel over money, or bad blood shows why.
##   collision  one vehicle shows damage matching what was hit (and no earlier damage), and one person is tied to it
##              at that time: their own story of how it was damaged, or the workshop's repair book; driving on is
##              panic.
## Rumours, suspicions ("If you ask me ...") and a vehicle glimpsed in the dark never decide anything. The sealed
## truth is opened only afterwards, by case_generate.gd, to check the conclusion.
extends RefCounted

const Investigation = preload("res://scripts/core/investigation.gd")

const PRESS_ORDER := ["incident", "window", "whereabouts", "money", "conflicts", "vehicles", "rumors", "past"]
const FIRST_HAND := ["saw", "heard", "self"]
## Money trouble, as people put it (case_text.gd). [pattern, group naming the person, or "speaker"]
const MONEY := [
	["(?<s>{N}) has been short of money", "s"],
	["(?<s>{N}) struggling for money", "s"],
	["(?<s>{N}) came asking me for money", "s"],
	["(?<s>{N}) has been taking food on credit", "s"],
	["(?<s>{N}) is behind on paying", "s"],
	["(?<s>{N}) owes me \\d+ crowns and is late paying", "s"],
	["(?<s>{N}) couldn't pay (me )?the rent", "s"],
	["(?<s>{N}) miss the rent", "s"],
	["turn (?<s>{N}) down for", "s"],
	["refused (?<s>{N}) (a loan|credit|money)", "s"],
	["I turned (?<s>{N}) down when they asked me for", "s"],
	["^I asked {N} for .*They said no", "speaker"],
	["^I'm behind on paying", "speaker"],
	["^I've been taking food on credit", "speaker"],
	["^I couldn't make the rent", "speaker"],
]
## Bad blood between two people: [pattern, "speaker" if the speaker is one of them]
const GRUDGE := [
	["bad blood between (?<a>{N}|them) and (?<b>{N}|them)", ""],
	["^(?<a>{N}) and I have never got on", "speaker"],
	["(?<a>{N}) confront(ed)? (?<b>{N}|them)", ""],
	["^I had it out with (?<a>{N})", "speaker"],
	["^(?<a>{N}) came at me", "speaker"],
]

var inv
var data: Dictionary
var hook: Dictionary
var w0 := 0
var w1 := 0
var scene := ""
var residents := {}
var by_first := {}
var names := ""
var entries := {}
var statements := []  # [entry, item]: every plain statement in the notebook (not the summaries)
var ev := {}  # rid -> kind -> [entry ids]
var pairs := {}  # rid -> [[own entry, other entry, kind]]
var contradictions := []
var counts := {"questions": 0, "pressed": 0, "places": 0, "vehicles": 0, "books": 0}


static func blind_view(pkg: Dictionary) -> Dictionary:
	## The player's side of a package and nothing else.
	return {"format": pkg["format"], "format_version": pkg["format_version"], "case_id": pkg["case_id"],
			"investigation": pkg["investigation"].duplicate(true)}


func _init(pkg: Dictionary, investigation = null) -> void:
	## With an investigation, play that one (a player's game opened from the full package, to show that the same
	## reasoning works through loading, saving and the reveal); without, a blind one made from the player's view.
	inv = investigation if investigation != null else Investigation.new(blind_view(pkg))
	if investigation == null:
		inv.state["mode"] = "experienced"
	data = inv.data
	hook = data["hook"]
	w0 = int(hook["window"][0])
	w1 = int(hook["window"][1])
	scene = String(hook["place"])
	var firsts := []
	for r in data["residents"]:
		residents[r["id"]] = r
		if not by_first.has(r["first"]):
			by_first[r["first"]] = []
			firsts.append(r["first"])
		by_first[r["first"]].append(r["id"])
	firsts.sort_custom(func(a, b): return a.length() > b.length() or (a.length() == b.length() and a < b))
	var parts := PackedStringArray()
	for f in firsts:
		parts.append(escape(f))
	names = "|".join(parts)


func run() -> Dictionary:
	## {"ok", "reason", "mechanism", "responsible", "motive", "cites", "cite_refs", "route", "counts"}; with ok the
	## theory has been submitted to the (blind) investigation.
	gather()
	read_notebook()
	var d := decide()
	d["counts"] = counts.duplicate()
	d["counts"]["notebook"] = inv.state["entries"].size()
	d["counts"]["contradictions"] = contradictions.size()
	if not d["ok"]:
		return d
	var res: Dictionary = inv.submit(d["mechanism"], d["responsible"], d["motive"], d["cites"], d["summary"])
	if res.has("error"):
		return {"ok": false, "reason": "the theory was refused: " + String(res["error"]), "counts": d["counts"]}
	var refs := []
	for eid in d["cites"]:
		refs.append(inv.entry(eid)["ref"])
	d["cite_refs"] = refs
	return d


# ================================================================ finding things out
func gather() -> void:
	## What a dodge or a hesitation sounds like: worth pressing on (a smooth talker gives no sign while saying something).
	var signals_text := [Investigation.EVASIVE["nervous"], Investigation.EVASIVE["smooth"], Investigation.HESITATE["nervous"]]
	for r in data["residents"]:
		var rid: String = r["id"]
		if r["condition"] == "deceased" or not data["testimony"].has(rid):
			continue
		var signals := []
		for t in inv.topics(rid):
			var topic: String = t[0]
			var res: Dictionary = inv.ask(rid, topic)
			counts["questions"] += 1
			for line in res.get("lines", []):
				if line["text"] in signals_text and not (topic in signals):
					signals.append(topic)
			_exhaust(rid, topic)
		var order: Array = signals.duplicate()
		for topic in PRESS_ORDER:
			if not (topic in order):
				order.append(topic)
		for topic in order:
			if int(inv.state["goodwill"].get(rid, 0)) <= 0:
				break
			if inv.state["pressed"].get(rid, []).has(topic):
				continue
			inv.ask(rid, topic, true)
			counts["questions"] += 1
			counts["pressed"] += 1
			_exhaust(rid, topic)
	for p in data["places"]:
		inv.inspect_place(p["id"])
		counts["places"] += 1
	for v in data["vehicles"]:
		inv.inspect_vehicle(v["id"])
		counts["vehicles"] += 1
	var books: Array = data["records"].keys()
	books.sort()
	for book in books:
		var res: Dictionary = inv.read(book)
		counts["books"] += 1
		for e in res.get("entries", []):
			inv.cite_record(e["id"])


func _exhaust(rid: String, topic: String) -> void:
	## "Tell me more" until there is no more, then "and before that?", and more again.
	for i in range(30):
		if not inv.follow_ups(rid, topic)["can_more"]:
			break
		inv.ask(rid, topic, false, "more")
		counts["questions"] += 1
	if inv.follow_ups(rid, topic)["can_earlier"]:
		inv.ask(rid, topic, false, "earlier")
		counts["questions"] += 1
		for i in range(30):
			if not inv.follow_ups(rid, topic)["can_more"]:
				break
			inv.ask(rid, topic, false, "more")
			counts["questions"] += 1


# ================================================================ reading the notebook
static func escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if ch in "\\.^$|?*+()[]{}/" else ch
	return out


func rx(pattern: String) -> RegEx:
	var r := RegEx.new()
	r.compile(pattern.replace("{N}", "(?:%s)" % names))
	return r


func rid_of(first: String, speaker = null):
	if (first == "I" or first == "me") and speaker != null:
		return speaker
	var ids: Array = by_first.get(first, [])
	return ids[0] if ids.size() == 1 else null


func item_of(eid: String) -> Dictionary:
	var e: Dictionary = entries.get(eid, {})
	if e.get("source") != "statement" or e.get("ref") == null:
		return {}
	return inv.item(String(e["ref"]))


func first_hand(eid: String) -> bool:
	var e: Dictionary = entries[eid]
	if e["source"] == "record":
		return true
	return String(item_of(eid).get("source", "")) in FIRST_HAND


func _add(rid, kind: String, eid: String) -> void:
	if rid == null:
		return
	if not ev.has(rid):
		ev[rid] = {}
	if not ev[rid].has(kind):
		ev[rid][kind] = []
	if not (eid in ev[rid][kind]):
		ev[rid][kind].append(eid)


func scene_household() -> Array:
	var p: Dictionary = inv.place(scene)
	var out := []
	for r in data["residents"]:
		if r["home"] == scene or r["id"] in p.get("owners", []):
			out.append(r["id"])
	return out


func read_notebook() -> void:
	for e in inv.state["entries"]:
		entries[e["id"]] = e
		if e["source"] == "statement" and e.get("ref") != null:
			var it: Dictionary = inv.item(String(e["ref"]))
			if not it.is_empty() and it.get("members", []).is_empty():
				statements.append([e, it])
	contradictions = inv.timeline()["contradictions"]
	# whose own account of the time in question does the notebook prove false, and with what
	for c in contradictions:
		if int(c["overlap"][1]) < w0 - 60 or int(c["overlap"][0]) > w1 + 60:
			continue
		var who: String = c["who"]
		for p in c["pairs"]:
			if not (p[2] in ["firm", "document"]):
				continue
			for pr in [[p[0], p[1]], [p[1], p[0]]]:
				var own: String = pr[0]
				var other: String = pr[1]
				if entries[own]["source"] != "statement" or entries[own].get("speaker") != who:
					continue
				if item_of(own).get("source") != "self" or not first_hand(other):
					continue
				var kind := "lie_witness"
				if entries[other]["source"] == "record":
					kind = "lie_record"
				elif entries[other].get("speaker") == who:
					kind = "lie_self"
				_add(who, kind, own)
				_add(who, kind, other)
				if not pairs.has(who):
					pairs[who] = []
				pairs[who].append([own, other, kind])
	# money trouble and bad blood, as people describe them
	var hh := scene_household()
	var money := []
	for m in MONEY:
		money.append([rx(m[0]), m[1]])
	var grudge := []
	for g in GRUDGE:
		grudge.append([rx(g[0]), g[1]])
	var teller_rx := rx("^(?<t>{N}) told me")
	for pair in statements:
		var e: Dictionary = pair[0]
		var it: Dictionary = pair[1]
		var sp: String = e["speaker"]
		var text: String = it["text"]
		for m in money:
			var found: RegExMatch = m[0].search(text)
			if found != null:
				_add(sp if m[1] == "speaker" else rid_of(found.get_string(m[1]), sp), "money", e["id"])
		var tm := teller_rx.search(text)
		var them = rid_of(tm.get_string("t")) if tm != null else sp
		for g in grudge:
			var found: RegExMatch = g[0].search(text)
			if found == null:
				continue
			var ids := []
			for k in ["a", "b"]:
				if not found.names.has(k):
					continue
				var nm := found.get_string(k)
				if nm == "":
					continue
				var who = them if nm == "them" else rid_of(nm, sp)
				if who != null:
					ids.append(who)
			if g[1] == "speaker":
				ids.append(sp)
			for i in ids:
				for j in ids:
					if i != j and j in hh and not (i in hh):
						_add(i, "grudge", e["id"])


# ================================================================ reasoning
func decide() -> Dictionary:
	var kind: String = hook["kind"]
	if kind in ["money_missing", "goods_missing"]:
		return decide_theft()
	if kind == "property_damaged":
		return decide_collision()
	if kind in ["person_injured", "person_dead"]:
		var a := decide_assault()
		var c := decide_collision()
		if a["ok"] and c["ok"]:
			return {"ok": false, "reason": "the evidence points both at an attack and at a vehicle"}
		if a["ok"]:
			return a
		if c["ok"]:
			return c
		return {"ok": false, "reason": "%s; %s" % [a["reason"], c["reason"]]}
	return {"ok": false, "reason": "no line of reasoning for this kind of case"}


func lie_kinds(rid: String) -> Array:
	var e: Dictionary = ev.get(rid, {})
	var out := []
	if e.has("lie_record"):
		out.append("lie_record")
	if e.has("lie_self"):
		out.append("lie_self")
	var wits := []
	for p in pairs.get(rid, []):
		if p[2] == "lie_witness":
			var sp = entries[p[1]].get("speaker")
			if sp != rid and not (sp in wits):
				wits.append(sp)
	if wits.size() >= 2:
		out.append("lie_witnesses")
	return out


func best(eids: Array) -> String:
	## A first-hand statement if there is one.
	for e in eids:
		if first_hand(e):
			return e
	return eids[0]


func decide_theft() -> Dictionary:
	var cands := []
	var suspects: Array = ev.keys()
	suspects.sort()
	for rid in suspects:
		if not lie_kinds(rid).is_empty():
			cands.append(rid)
	if cands.is_empty():
		for rid in suspects:
			if pairs.has(rid):
				return {"ok": false, "reason": "nobody's account of the time in question is proven false (at most one witness against an account: word against word)"}
		return {"ok": false, "reason": "nobody's account of the time in question is proven false"}
	if cands.size() > 1:
		return {"ok": false, "reason": "more than one account of the time in question is proven false"}
	var rid: String = cands[0]
	var lies := lie_kinds(rid)
	var e: Dictionary = ev[rid]
	var motive := ""
	var mx := ""
	if e.has("money"):
		motive = "money_trouble"
		mx = best(e["money"])
	elif e.has("grudge"):
		motive = "grudge"
		mx = best(e["grudge"])
	else:
		return {"ok": false, "reason": "the one false account belongs to someone with no motive anyone knows of"}
	# the entries it rests on: the account, what disproves it (records first, else one statement per witness), why
	var own := []
	var against := []
	var seen := []
	for p in pairs[rid]:
		if (p[2] == "lie_record" and "lie_record" in lies) or (p[2] == "lie_self" and "lie_self" in lies):
			if against.size() < 2 and not (p[1] in against):
				against.append(p[1])
				if not (p[0] in own):
					own.append(p[0])
	if against.is_empty():
		for p in pairs[rid]:
			var sp = entries[p[1]].get("speaker")
			if p[2] == "lie_witness" and not (sp in seen) and seen.size() < 2:
				seen.append(sp)
				against.append(p[1])
				if not (p[0] in own):
					own.append(p[0])
	var cites: Array = own.slice(0, 1) + against + [mx]
	var route := ["false account (%s)" % ", ".join(PackedStringArray(lies)), "motive (%s)" % motive]
	return {"ok": true, "mechanism": "stolen", "responsible": rid, "motive": motive, "cites": cites, "route": route,
			"summary": "%s's account of the time in question is false, and they had reason to steal." % residents[rid]["first"]}


func hook_victims() -> Array:
	var out := []
	for r in data["residents"]:
		if String(r["name"]) in String(hook["text"]):
			out.append(r["id"])
	return out


func near(t, pad := 90) -> bool:
	return t != null and w0 - pad <= int(t) and int(t) <= w1 + pad


func drunk(rid: String, t0: int, t1: int) -> String:
	## An entry that shows them drunk shortly before: someone saw them the worse for drink, or the bar tab has them
	## at three drinks or more.
	var seen_drunk := rx("^I saw (?<s>{N}) the worse for drink at")
	for pair in statements:
		var it: Dictionary = pair[1]
		var m := seen_drunk.search(it["text"])
		if m != null and rid_of(m.get_string("s")) == rid and it["time"] != null and t0 <= int(it["time"]) \
				and int(it["time"]) <= t1:
			return pair[0]["id"]
	var tab := RegEx.new()
	tab.compile(escape(String(residents[rid]["name"])) + ": (?<n>\\d+) drinks? \\(")
	var total := 0
	var last := ""
	for e in inv.state["entries"]:
		if e["source"] != "record" or e["time"] == null or int(e["time"]) < t0 or int(e["time"]) > t1:
			continue
		var m := tab.search(String(e["text"]))
		if m != null:
			total += int(m.get_string("n"))
			last = e["id"]
	return last if total >= 3 else ""


func decide_assault() -> Dictionary:
	var victims := hook_victims()
	var named := {}
	var order := []
	var attacked := rx("^(?<s>{N}) attacked me at")
	var saw := rx("^I saw (?<s>{N}) attack (?<v>{N}) at")
	for pair in statements:
		var e: Dictionary = pair[0]
		var it: Dictionary = pair[1]
		if not near(it["time"]):
			continue
		var sp: String = e["speaker"]
		var m: RegExMatch = null
		if it["source"] == "self":
			m = attacked.search(it["text"])
		elif it["source"] == "saw":
			m = saw.search(it["text"])
		if m == null:
			continue
		var who = rid_of(m.get_string("s"))
		if who == null or who == sp or (who in victims and victims.size() == 1):
			continue
		if not named.has(who):
			named[who] = []
			order.append(who)
		named[who].append(e["id"])
	if named.is_empty():
		return {"ok": false, "reason": "nobody who was there names an attacker"}
	if named.size() > 1:
		return {"ok": false, "reason": "people who were there name different attackers"}
	var rid: String = order[0]
	var cites: Array = named[rid].slice(0, 3)
	var d := drunk(rid, w0 - 300, w1 + 30)
	if d != "":
		return {"ok": true, "mechanism": "assaulted", "responsible": rid, "motive": "intoxication", "cites": cites + [d],
				"route": ["named by someone who was there", "drunk"],
				"summary": "%s attacked them, the worse for drink." % residents[rid]["first"]}
	var argue := rx("(confront(ed)?|had it out with|came at me)")
	var money_arg := ""
	var grudge_arg := ""
	for pair in statements:
		var e: Dictionary = pair[0]
		var it: Dictionary = pair[1]
		var text: String = it["text"]
		if not (rid in it["about"]) and e["speaker"] != rid:
			continue
		var with_victim := false
		for v in victims:
			if v in it["about"] or e["speaker"] == v:
				with_victim = true
		if not with_victim:
			continue
		if argue.search(text) != null:
			if "money owed" in text:
				money_arg = money_arg if money_arg != "" else e["id"]
			else:
				grudge_arg = grudge_arg if grudge_arg != "" else e["id"]
		elif "never got on" in text or "bad blood" in text:
			grudge_arg = grudge_arg if grudge_arg != "" else e["id"]
	if money_arg != "":
		return {"ok": true, "mechanism": "assaulted", "responsible": rid, "motive": "money_trouble",
				"cites": cites + [money_arg], "route": ["named by someone who was there", "a quarrel over money"],
				"summary": "%s attacked them in a quarrel over money." % residents[rid]["first"]}
	if grudge_arg != "":
		return {"ok": true, "mechanism": "assaulted", "responsible": rid, "motive": "grudge",
				"cites": cites + [grudge_arg], "route": ["named by someone who was there", "bad blood"],
				"summary": "%s attacked them out of anger." % residents[rid]["first"]}
	return {"ok": false, "reason": "the attacker is named, but nothing shows why"}


func decide_collision() -> Dictionary:
	var fence := "fence" in String(hook["text"])
	var marks: Array = ["white paint", "splinters"] if fence else ["smear", "windscreen", "dark stain"]
	var vehicles := {}
	var by_name := {}
	var vnames := []
	for v in data["vehicles"]:
		vehicles[v["id"]] = v
		by_name[v["name"]] = v["id"]
		vnames.append(v["name"])
	if vehicles.is_empty():
		return {"ok": false, "reason": "there are no vehicles in town"}
	vnames.sort_custom(func(a, b): return a.length() > b.length() or (a.length() == b.length() and a < b))
	var alt := PackedStringArray()
	for n in vnames:
		alt.append(escape(n))
	var vn_rx := "(?:%s)" % "|".join(alt)
	var marks_rx := "(?:%s)" % "|".join(PackedStringArray(marks))
	var damaged := {}  # vehicle -> [entry ids showing damage like this since the time in question]
	var before := {}  # vehicle -> time it was last known damaged before the time in question
	var drivers := {}  # rid -> [entry ids tying them to the vehicle]: filled below
	var repairs := []  # [vehicle, entry id, customer rid or null, time]: every workshop line about a vehicle
	var scrap := []  # [vehicle, entry id]: mended parts in the workshop scrap pile
	var chalked := RegEx.new()
	chalked.compile("chalked '(?<v>%s)'" % vn_rx)
	var mark_rx := RegEx.new()
	mark_rx.compile(marks_rx)
	for e in inv.state["entries"]:
		if e["source"] == "trace" and mark_rx.search(String(e["text"])) != null:
			for vid in vehicles:
				for tr in vehicles[vid]["traces"]:
					if tr["id"] == e["ref"]:
						_put(damaged, vid, e["id"])
			var m := chalked.search(String(e["text"]))
			if m != null:
				scrap.append([by_name[m.get_string("v")], e["id"]])
		if e["source"] == "record" and e["time"] != null:
			var line := String(e["text"])
			for vid in vehicles:
				var vname: String = vehicles[vid]["name"]
				if not (line.contains(vname + " (") or line.contains("for %s (workshop's own)" % vname)):
					continue
				var customer = null
				for r in data["residents"]:
					if line.contains("%s (%s)" % [vname, r["name"]]):
						customer = r["id"]
				repairs.append([vid, e["id"], customer, int(e["time"])])
	var seen_damage := RegEx.new()
	seen_damage.compile("^I saw (?<v>%s) with .*%s" % [vn_rx, marks_rx])
	var owned := RegEx.new()
	owned.compile("^I hit .* on Mill Road .*, driving (?<v>%s)\\. I stopped and owned up" % vn_rx)
	for pair in statements:
		var e: Dictionary = pair[0]
		var it: Dictionary = pair[1]
		if it["time"] == null:
			continue
		var t := int(it["time"])
		var m: RegExMatch = seen_damage.search(it["text"]) if it["source"] == "saw" else null
		var o := owned.search(it["text"])
		var vid = null
		if m != null:
			vid = by_name[m.get_string("v")]
			if t >= w0:
				_put(damaged, vid, e["id"])
		elif o != null:
			vid = by_name[o.get_string("v")]
		if vid != null and t < w0 and t > int(before.get(vid, -1)):
			before[vid] = t
	# damage known from before the time in question does not count against a vehicle mended since; a repair after it
	# shows the vehicle needed one (and the mended parts in the scrap pile are from then)
	var mended_after := {}
	for rp in repairs:
		if rp[3] >= w0:
			_put(damaged, rp[0], rp[1])
			mended_after[rp[0]] = true
		elif before.has(rp[0]) and rp[3] > int(before[rp[0]]):
			before.erase(rp[0])
	for sc in scrap:
		if mended_after.has(sc[0]):
			_put(damaged, sc[0], sc[1])
	var cands := []
	var earlier := []
	var vids: Array = damaged.keys()
	vids.sort()
	for vid in vids:
		if before.has(vid):
			earlier.append(vehicles[vid]["name"])
		else:
			cands.append(vid)
	if cands.is_empty():
		var why := "" if earlier.is_empty() else " (%s was already damaged before the time in question)" % ", ".join(PackedStringArray(earlier))
		return {"ok": false, "reason": "no vehicle can be shown to carry damage from it" + why}
	if cands.size() > 1:
		return {"ok": false, "reason": "more than one vehicle carries damage like it"}
	var vid: String = cands[0]
	var vname: String = vehicles[vid]["name"]
	var deer := RegEx.new()
	deer.compile("^%s\\? I hit a deer" % escape(vname.substr(0, 1).to_upper() + vname.substr(1)))
	var brought := rx("^I saw (?<s>{N}) bring %s in for repairs" % escape(vname))
	var order := []
	for pair in statements:
		var e: Dictionary = pair[0]
		var it: Dictionary = pair[1]
		if it["source"] == "self" and deer.search(it["text"]) != null:
			if _put(drivers, e["speaker"], e["id"]):
				order.append(e["speaker"])
		var m: RegExMatch = brought.search(it["text"]) if it["source"] == "saw" else null
		if m != null and it["time"] != null and int(it["time"]) >= w0:
			var who = rid_of(m.get_string("s"))
			if who != null and _put(drivers, who, e["id"]):
				order.append(who)
	for rp in repairs:
		if rp[0] == vid and rp[3] >= w0 and rp[2] != null and _put(drivers, rp[2], rp[1]):
			order.append(rp[2])
	if drivers.is_empty():
		return {"ok": false, "reason": "nothing ties anyone to the %s at the time" % vname}
	if drivers.size() > 1:
		return {"ok": false, "reason": "more than one person is tied to the %s" % vname}
	var rid: String = order[0]
	var cites: Array = Array(damaged[vid]).slice(0, 1) + Array(drivers[rid]).slice(0, 2)
	return {"ok": true, "mechanism": "vehicle_collision" if fence else "struck_by_vehicle", "responsible": rid,
			"motive": "panic", "cites": cites, "route": ["the damaged vehicle", "its driver", "drove on"],
			"summary": "%s was driving the %s and drove on." % [residents[rid]["first"], vname]}


static func _put(d: Dictionary, k, v) -> bool:
	## Adds v under k; true if k is new.
	var fresh := not d.has(k)
	if fresh:
		d[k] = []
	if not (v in d[k]):
		d[k].append(v)
	return fresh
