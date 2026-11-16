## Evidence relevance: does a piece of information connect to the incident? (mirrors mystery/cases/relevance.py)
##
## Every statement, trace and record line in a case gets one of three verdicts, derived from the simulation's
## causal record, never from keywords or hand-written labels:
##   connected  it stems from an event in the incident's causal web: the act, what led to it, what followed from
##              it, and the responsible person's trip to and from the scene;
##   unrelated  it stems from an event outside that web, or, for where-and-when information, it puts nobody where
##              and when any part of the incident happened;
##   uncertain  where-and-when information that does put someone where and when part of the incident happened
##              (whether that matters depends on who and whether it is true, which a check must never reveal), or
##              hearsay that cannot be traced back to anything anyone perceived.
## Truth-blind: a verdict never depends on whether a statement is accurate, mistaken or a lie (hearsay is judged by
## its first perception, a lie by what it covers). Identity-blind where it matters: whereabouts are judged by
## place and time only, so checking an alibi or a sighting can never single out the culprit. Sealed, like the rest
## of the truth (case_builder.gd).
extends RefCounted

const VERDICTS := ["connected", "unrelated", "uncertain"]
## Information about where someone was (and in what state) rather than about an event.
const WHERE_KINDS := ["presence", "sighting", "intoxicated"]
## Witness times are approximate and memories drift; a claim "touches" a moment within this margin.
const MARGIN := 45


static func web(b) -> Array:
	## The incident's causal web: the case's chain plus the responsible person's trip to the scene before the act
	## and from it afterwards.
	var sim = b.sim
	var inc: Dictionary = b.inc
	var ids: Array = Array(b.chain).duplicate()
	var core: Dictionary = sim.events.by_id[inc["core_event"]]
	if inc["responsible"] != null:
		var before = null
		var after = null
		for ev in sim.events.events:
			if ev["kind"] != "move" or not (inc["responsible"] in ev["actors"]) or int(ev["time"]) > b.now:
				continue
			var path: Array = ev["data"].get("path", [])
			if not path.is_empty() and path[-1] == core["location"] and int(ev["time"]) <= int(core["time"]):
				before = ev["id"]
			if not path.is_empty() and path[0] == core["location"] and int(ev["time"]) >= int(core["time"]) and after == null:
				after = ev["id"]
		for e in [before, after]:
			if e != null and not (e in ids):
				ids.append(e)
	return ids


static func footprint(b, web_ids: Array) -> Array:
	## [place, minute] for each part of the incident, including every stop on the trips.
	var out := []
	for eid in web_ids:
		var ev: Dictionary = b.sim.events.by_id[eid]
		var path: Array = ev["data"].get("path", []) if ev["data"] is Dictionary else []
		var times: Array = ev["data"].get("times", []) if ev["data"] is Dictionary else []
		if ev["kind"] == "move" and not path.is_empty() and path.size() == times.size():
			for i in path.size():
				out.append([path[i], times[i]])
		else:
			out.append([ev["location"], ev["time"]])
	return out


static func _touches(facts: Array, marks: Array) -> bool:
	for f in facts:
		for m in marks:
			if f[0] == m[0] and int(f[1]) - MARGIN <= int(m[1]) and int(m[1]) <= int(f[2]) + MARGIN:
				return true
	return false


static func root(sim, belief: Dictionary) -> Dictionary:
	## Follow hearsay back to whoever first perceived (or worked out) the thing.
	var seen := 0
	while belief["source"] == "told" and belief["via"] != null and sim.beliefs.has(belief["via"]) and seen < 30:
		belief = sim.beliefs[belief["via"]]
		seen += 1
	return belief


static func judge(b, evidence: Dictionary, records: Dictionary) -> Dictionary:
	## {ref: {verdict, reason, source, kind}} for every statement key (summaries excepted), trace id and record id.
	var sim = b.sim
	var web_ids := web(b)
	var in_web := {}
	for e in web_ids:
		in_web[e] = true
	var marks := footprint(b, web_ids)
	var out := {}
	var speakers: Array = b.items.keys()
	speakers.sort()
	for rid in speakers:
		for it in b.items[rid]:
			var ref: String = it["key"]
			var a: Dictionary = b.audit[ref]
			if a.get("summary", false):
				continue  # a summary is checked through the statements it stands for, one by one
			var belief = sim.beliefs.get(a["belief"]) if a.get("belief") != null else null
			var claim_kind := "other"
			if belief != null:
				claim_kind = belief["claim"]["kind"]
			elif a.has("segments"):
				claim_kind = "account"
			if a.has("segments") or claim_kind in WHERE_KINDS:
				var facts := []
				for f in it.get("facts", []):
					facts.append([f["place"], f["from"], f["to"]])
				if facts.is_empty() and it.get("place") != null and it.get("time") != null:
					facts.append([it["place"], it["time"], it["time"]])
				var hit := _touches(facts, marks)
				out[ref] = {"verdict": "uncertain" if hit else "unrelated", "reason": "where_when" if hit else "outside",
						"source": null, "kind": claim_kind}
				continue
			if a.get("about_event") != null:
				out[ref] = _by_event(a["about_event"], in_web, claim_kind)  # a made-up story is judged by what it covers
				continue
			if belief == null:
				out[ref] = _by_event(null, in_web, claim_kind)
				continue
			var first := root(sim, belief)
			if first["source"] == "told" and first["via"] != null:
				out[ref] = _by_event(null, in_web, claim_kind)  # the trail of telling breaks off
				continue
			var event = first["event"]
			if event == null and first["claim"]["kind"] == "suspect":
				var target: Dictionary = b.incident_for_claim(first["claim"])
				event = target["core_event"] if not target.is_empty() else null
			out[ref] = _by_event(event, in_web, claim_kind)
	for at in evidence:
		for e in evidence[at]:
			out["T-" + String(e["id"])] = _by_event(e["created_by"], in_web, "trace")
	for book in records:
		for x in records[book]["entries"]:
			out["R-" + String(x["id"])] = _by_event(x["event"], in_web, "record")
	return out


static func _by_event(event, in_web: Dictionary, kind: String) -> Dictionary:
	if event == null:
		return {"verdict": "uncertain", "reason": "untraced", "source": null, "kind": kind}
	var linked := in_web.has(event)
	return {"verdict": "connected" if linked else "unrelated", "reason": "web" if linked else "outside",
			"source": event, "kind": kind}
