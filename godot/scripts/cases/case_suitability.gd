## Is a case investigable, and how? (mirrors mystery/cases/suitability.py, Pilot 4B)
##
## Two questions are kept apart: did something interesting happen (the incident), and can a careful player
## reasonably infer anything about it (this module). A case is judged by its independent channels: separate
## witnesses, physical traces, documentary records and contradictions that point at what really happened and are
## actually reachable by the player at the moment the case starts. This is the developer's report, sealed with the
## truth; it is worked out from the truth (who is accurate, who lies) and so can never decide on its own whether a
## case is playable: the truth-blind investigator (case_solver.gd) does that, from the player's view alone.
## hints() writes the ladder of hints, which only ever point at things the player can actually find.
extends RefCounted

const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Investigation = preload("res://scripts/core/investigation.gd")

const VERDICTS := ["obvious", "playable", "ambiguous", "unsolvable"]
const RESPONSIBLE_TAGS := ["places_responsible", "act", "vehicle", "absence", "sudden_money"]
const ORDER := {"contradiction": 0, "documentary": 1, "physical": 2, "witness": 3}


static func _has_any(values: Array, wanted: Array) -> bool:
	for v in values:
		if v in wanted:
			return true
	return false


static func evaluate(b, consent: Dictionary, evidence: Dictionary, records: Dictionary) -> Dictionary:
	var sim = b.sim
	var inc: Dictionary = b.inc
	var R = inc["responsible"]
	var in_chain := {}
	for e in b.chain:
		in_chain[e] = true
	var channels := []
	var misleading := {}  # speaker -> true
	var eyewitnesses := []

	# --- testimony: one channel per independent witness
	var by_speaker := {}
	for key in b.audit:
		var a: Dictionary = b.audit[key]
		if String(key).begins_with("W-") or a.get("summary", false):
			continue  # summaries repeat their members; they are not separate witnesses
		var sup: Array = a.get("supports", [])
		if "misleading" in sup:
			misleading[a["speaker"]] = true
		if a["status"] != "accurate" or a["speaker"] == R:
			continue
		var resp := []
		for s in sup:
			if s in RESPONSIBLE_TAGS:
				resp.append(s)
		var mech: bool = "mechanism" in sup
		if resp.is_empty() and not mech:
			continue
		var root: String = a["speaker"] if a.get("root") == null or String(a.get("root")) == "" else String(a["root"])
		if root == R:
			continue  # the culprit's own words, retold, are not independent evidence
		if not by_speaker.has(root):
			by_speaker[root] = {"keys": [], "responsible": false, "mechanism": false, "direct": false,
					"circumstantial": true, "guarded_only": true, "speakers": []}
		var ch: Dictionary = by_speaker[root]
		ch["keys"].append(key)
		if not (a["speaker"] in ch["speakers"]):
			ch["speakers"].append(a["speaker"])
		ch["responsible"] = ch["responsible"] or not resp.is_empty()
		ch["circumstantial"] = ch["circumstantial"] and (resp.is_empty() or resp == ["sudden_money"])
		ch["mechanism"] = ch["mechanism"] or mech
		ch["direct"] = ch["direct"] or (a["source"] in ["saw", "self", "heard"] and a["speaker"] == root)
		ch["guarded_only"] = ch["guarded_only"] and a.get("disclosure") == "guarded"
		if "act" in sup:
			eyewitnesses.append(root)
	var roots: Array = by_speaker.keys()
	roots.sort()
	for root in roots:
		var ch: Dictionary = by_speaker[root]
		var strength := "strong" if ch["direct"] and not (ch["responsible"] and ch["circumstantial"]) else "hearsay"
		channels.append({"type": "witness", "source": root, "speakers": ch["speakers"], "keys": ch["keys"].slice(0, 6),
				"points_to": "responsible" if ch["responsible"] else "mechanism", "strength": strength,
				"needs_pressing": ch["guarded_only"]})

	# --- contradictions: the responsible person's lie against an accurate account or a record, as the player's own
	# timeline would show it (a firm clash or a record against a statement, not a matter of approximate times)
	var lies := []
	for k in b.audit:
		var a: Dictionary = b.audit[k]
		if a.get("lie", false) and a["speaker"] == R and not String(k).begins_with("W-") and a.get("exact_of") == null:
			lies.append(k)
	var exposing: Array = exposed_lies(b, consent, records, lies) if not lies.is_empty() else []
	if not exposing.is_empty():
		var keys := []
		var guarded_only := true
		for pair in exposing:
			for k in pair:
				if not (k in keys):
					keys.append(k)
				if not String(k).begins_with("R-") and b.audit.get(k, {}).get("disclosure") != "guarded":
					guarded_only = false
		channels.append({"type": "contradiction", "source": R, "keys": keys.slice(0, 6), "points_to": "responsible",
				"strength": "strong", "needs_pressing": guarded_only})

	# --- physical traces
	var places: Array = evidence.keys()
	places.sort()
	for at in places:
		var allowed := true
		if consent.has(at):
			allowed = consent[at]["allowed"]
		else:
			var vloc: String = sim.world.vehicles[at]["location"]
			allowed = sim.world.locations[vloc]["kind"] != "home" or consent[vloc]["allowed"]
		var linked := []
		var implicating := false
		for e in evidence[at]:
			var imp: bool = R != null and R in e["implicates"]
			if in_chain.has(e["created_by"]) or imp:
				linked.append("T-" + String(e["id"]))
				implicating = implicating or imp
		if not linked.is_empty():
			channels.append({"type": "physical", "source": at, "keys": linked,
					"points_to": "responsible" if implicating else "mechanism",
					"strength": "strong" if allowed else "blocked", "needs_pressing": false})

	# --- documentary records
	var d0: int = int(inc["time"]) - 6 * 60
	var d1: int = int(inc["time"])
	var books: Array = records.keys()
	books.sort()
	for book in books:
		var data: Dictionary = records[book]
		var allowed: bool = consent[data["place"]]["allowed"]
		var keys := []
		var resp := false
		for x in data["entries"]:
			var ev: Dictionary = sim.events.by_id[x["event"]]
			var linked: bool = in_chain.has(x["event"])
			var ref := "R-" + String(x["id"])
			if (ev["kind"] == "ledger_error" and inc["family"] == "accounting_error" and linked) \
					or (linked and ev["kind"] == "purchase"):
				keys.append(ref)
			elif linked and ev["kind"] in ["repair", "treated"]:
				keys.append(ref)
				resp = resp or (R != null and (R in ev["actors"] or R in ev["targets"]))
			elif R != null and ev["kind"] == "drink" and R in ev["actors"] and d0 <= int(ev["time"]) \
					and int(ev["time"]) <= d1 and inc["family"] in ["collision", "assault"]:
				keys.append(ref)
				resp = true
			elif inc["family"] == "fall" and ev["kind"] == "drink" and ev["actors"][0] in inc["victims"] \
					and d0 <= int(ev["time"]) and int(ev["time"]) <= d1:
				keys.append(ref)
		if not keys.is_empty():
			channels.append({"type": "documentary", "source": book, "keys": keys.slice(0, 6),
					"points_to": "responsible" if resp else "mechanism", "strength": "strong" if allowed else "blocked",
					"needs_pressing": false})

	var usable := []
	var strong := []
	for c in channels:
		if c["strength"] == "strong" or c["strength"] == "hearsay":
			usable.append(c)
		if c["strength"] == "strong":
			strong.append(c)
	# How the answer can be worked out from evidence, rather than guessed from motive and gossip
	var routes := []
	if R != null:
		if not exposing.is_empty():
			routes.append("contradiction")
		var victims_naming := false
		for k in b.audit:
			var a: Dictionary = b.audit[k]
			if String(k).begins_with("W-") or a.get("summary", false):
				continue
			var sup: Array = a.get("supports", [])
			if a["status"] == "accurate" and a["speaker"] != R and a["source"] == "self" and "places_responsible" in sup \
					and "mechanism" in sup:
				victims_naming = true
		if not eyewitnesses.is_empty() or victims_naming:
			routes.append("eyewitness")
		if only_one_there(b, consent, records) == R:
			routes.append("opportunity")
		for c in strong:
			if c["type"] in ["physical", "documentary"] and c["points_to"] == "responsible" and not (c["type"] in routes):
				routes.append(c["type"])
	else:
		for c in strong:
			if c["points_to"] == "mechanism" and c["type"] in ["physical", "documentary", "witness"]:
				var r: String = "%s (what happened)" % c["type"]
				if not (r in routes):
					routes.append(r)
	routes.sort()
	var verdict := ""
	if R != null:
		var resp := []
		var resp_strong := false
		for c in usable:
			if c["points_to"] == "responsible":
				resp.append(c)
				resp_strong = resp_strong or c["strength"] == "strong"
		if _distinct(eyewitnesses).size() >= 2 and usable.size() >= 3:
			verdict = "obvious"
		elif resp_strong and resp.size() >= 2:
			verdict = "playable"
		elif not resp.is_empty():
			verdict = "ambiguous"
		else:
			verdict = "unsolvable"
	else:
		var docs := false
		for c in strong:
			docs = docs or c["type"] in ["documentary", "physical"]
		if strong.size() >= 2 or docs:
			verdict = "playable"
		elif not usable.is_empty():
			verdict = "ambiguous"
		else:
			verdict = "unsolvable"
	var statuses := {}
	var mistakes := {}
	var n_statements := 0
	var n_summaries := 0
	var n_withheld := 0
	for key in b.audit:
		var a: Dictionary = b.audit[key]
		if a.get("summary", false):
			n_summaries += 1
		if String(key).begins_with("W-"):
			n_withheld += 1
		if String(key).begins_with("W-") or a.get("summary", false) or a.get("exact_of") != null:
			continue
		n_statements += 1
		statuses[a["status"]] = int(statuses.get(a["status"], 0)) + 1
		if a["status"] == "mistaken":
			var err: String = String(a["error"]) if a.get("error") != null and String(a["error"]) != "" else "unknown"
			mistakes[err] = int(mistakes.get(err, 0)) + 1
	var resp_channels := 0
	var blocked := 0
	for c in channels:
		if c["strength"] == "blocked":
			blocked += 1
	for c in usable:
		if c["points_to"] == "responsible":
			resp_channels += 1
	var eye := _distinct(eyewitnesses)
	eye.sort()
	return {
		"case_id": b.case_id,
		"family": inc["family"],
		"statement_status": statuses,
		"mistaken_by_cause": mistakes,
		"mechanism": inc["mechanism"],
		"outcome": inc["outcome"],
		"noticed": inc["discovered_at"] != null,
		"verdict": verdict,
		"deduction": routes,
		"solvable_by_evidence": not routes.is_empty(),
		"channels": channels,
		"independent_channels": usable.size(),
		"responsible_channels": resp_channels,
		"blocked_channels": blocked,
		"eyewitnesses": eye,
		"red_herrings": misleading.size(),
		"lies_by_responsible": lies.size(),
		"statements": n_statements,
		"summaries": n_summaries,
		"withheld": n_withheld,
	}


static func _distinct(values: Array) -> Array:
	var out := []
	for v in values:
		if not (v in out):
			out.append(v)
	return out


static func exposed_lies(b, consent: Dictionary, records: Dictionary, lies: Array) -> Array:
	## [lie, other] pairs where a lie of the responsible person clashes - firmly, or with a record - with an accurate
	## statement of someone else or a record line the player can read. Worked out exactly as the player's timeline
	## works out contradictions (Investigation.find_contradictions), each statement and record line standing in for
	## a notebook entry.
	var facts := []
	var info := {}
	var ref_of := {}  # notebook-style entry id -> statement key or record ref
	var n := 0
	var speakers: Array = b.items.keys()
	speakers.sort()
	for rid in speakers:
		for it in b.items[rid]:
			if b.audit[it["key"]].get("summary", false):
				continue
			n += 1
			var eid := "S%d" % n
			ref_of[eid] = it["key"]
			info[eid] = {"kind": "statement", "source": it["source"], "summary": false}
			for f in it["facts"]:
				facts.append({"entry": eid, "who": f["who"], "place": f["place"], "from": int(f["from"]),
						"to": int(f["to"]), "hedged": bool(f.get("hedged", false))})
	var m := 0
	var books: Array = records.keys()
	books.sort()
	for book in books:
		var data: Dictionary = records[book]
		if not consent[data["place"]]["allowed"]:
			continue
		for x in data["entries"]:
			var fx: Array = b._record_facts(x, data["place"])
			if fx.is_empty():
				continue
			m += 1
			var eid := "D%d" % m
			ref_of[eid] = "R-" + String(x["id"])
			info[eid] = {"kind": "record", "source": "record", "summary": false}
			for f in fx:
				facts.append({"entry": eid, "who": f["who"], "place": f["place"], "from": int(f["from"]),
						"to": int(f["to"]), "hedged": bool(f.get("hedged", false))})
	var told_in_full := {}
	for k in b.audit:
		var x = b.audit[k].get("exact_of")
		if x != null and x in lies:
			told_in_full[k] = x
	var out := []
	for c in Investigation.find_contradictions(facts, info):
		for p in c["pairs"]:
			if not (p[2] in ["firm", "document"]):
				continue
			var x: String = ref_of[p[0]]
			var y: String = ref_of[p[1]]
			for pair in [[x, y], [y, x]]:
				var lie: String = told_in_full.get(pair[0], pair[0])
				var other: String = pair[1]
				if not (lie in lies):
					continue
				var fair: bool = other.begins_with("R-")
				if not fair:
					var oa: Dictionary = b.audit[other]
					fair = oa["status"] == "accurate" and oa["speaker"] != b.inc["responsible"]
				if fair and not out.has([lie, other]):
					out.append([lie, other])
	return out


static func only_one_there(b, consent: Dictionary, records: Dictionary):
	## The one person that accurate statements and readable records put at the scene during the time in question, if
	## there is exactly one: whoever it is had the only opportunity, as the player can work out.
	var scene: String = b.inc["hook_place"]
	var w0: int = int(b.window[0])
	var w1: int = int(b.window[1])
	var there := {}
	for rid in b.items:
		for it in b.items[rid]:
			var a: Dictionary = b.audit[it["key"]]
			if a.get("summary", false) or a["status"] != "accurate":
				continue
			for f in it["facts"]:
				if f["place"] == scene and int(f["from"]) < w1 and int(f["to"]) > w0:
					there[f["who"]] = true
	for book in records:
		var data: Dictionary = records[book]
		if not consent[data["place"]]["allowed"]:
			continue
		for x in data["entries"]:
			for f in b._record_facts(x, data["place"]):
				if f["place"] == scene and w0 < int(f["from"]) and int(f["from"]) < w1:
					there[f["who"]] = true
	return there.keys()[0] if there.size() == 1 else null


static func hints(b, report: Dictionary) -> Array:
	## A ladder of hints that only ever point at things the player can actually find.
	var sim = b.sim
	var win := "%s on Day %d" % [SimClock.fmt_clock(int(b.window[0])), SimClock.day_of(int(b.window[0]))]
	var usable := []
	for c in report["channels"]:
		if c.get("strength") == "strong" or c.get("strength") == "hearsay":
			usable.append(c)
	usable.sort_custom(func(p, q): return _channel_less(p, q))
	if usable.is_empty():
		return [
			{"tier": 1, "cost": 1, "text": "Not every case leaves enough behind. It is fair to conclude that you cannot tell what happened."},
			{"tier": 2, "cost": 2, "text": "Look for anyone who was out and about during the time in question; if no one was, an 'unresolved' verdict is honest."},
		]
	var by_type := {
		"contradiction": "Not every account of the time in question holds together. Compare what people say about where they were.",
		"documentary": "Written records sometimes remember what people forget.",
		"physical": "Things left behind can say as much as people do.",
		"witness": "Someone was out and about at the time. Ask people what they saw or heard.",
	}
	var out := [{"tier": 1, "cost": 1, "text": by_type[usable[0]["type"]]}]
	var lead := ""
	for c in usable:
		if c["type"] == "witness":
			lead = "Ask %s what they saw or heard around %s." % [sim.residents[c["source"]].first, win]
		elif c["type"] == "documentary":
			lead = "Have a look at the %s." % String(sim.world.books[c["source"]]["title"]).to_lower()
		elif c["type"] == "physical":
			lead = "Take a careful look at %s." % sim.world.name_of(c["source"])
		if lead != "":
			break
	if lead != "":
		out.append({"tier": 2, "cost": 2, "text": lead})
	var strong := ""
	var contra := []
	var witness = null
	var docs := []
	var phys := []
	for c in usable:
		if c["type"] == "contradiction":
			contra.append(c)
		elif c["type"] == "witness" and witness == null:
			witness = c
		elif c["type"] == "documentary":
			docs.append(c)
		elif c["type"] == "physical":
			phys.append(c)
	if not contra.is_empty() and witness != null:
		strong = "Compare %s's account of where they were with what %s says about the same hours." % [
				sim.residents[contra[0]["source"]].first, sim.residents[witness["source"]].first]
	if strong == "" and not docs.is_empty():
		if b.inc["family"] == "accounting_error":
			strong = "Read the ledger line by line for the day the till came up short. Count the sales."
		else:
			strong = "The %s places someone at a telling time." % String(sim.world.books[docs[0]["source"]]["title"]).to_lower()
	if strong == "" and not phys.is_empty():
		strong = "What is at %s connects to the incident. Who could have left it?" % sim.world.name_of(phys[0]["source"])
	if strong == "" and usable.size() > 1 and usable[1]["type"] == "witness":
		strong = "%s also knows something about the time in question." % sim.residents[usable[1]["source"]].first
	if strong != "":
		out.append({"tier": 3, "cost": 3, "text": strong})
	return out


static func _channel_less(p: Dictionary, q: Dictionary) -> bool:
	if ORDER[p["type"]] != ORDER[q["type"]]:
		return ORDER[p["type"]] < ORDER[q["type"]]
	return String(p["source"]) < String(q["source"])
