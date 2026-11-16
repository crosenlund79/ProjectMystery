## Case extraction from the native simulation (Pilot 4A; mirrors snapshot_hook and the integrity checks of
## mystery/cases/export.py and mystery/diagnostics/integrity.py). No Python anywhere.
##
##   collect(cfg)           runs a town and freezes every case candidate at its case start, as the investigator
##                          arrives (case_builder.gd), without disturbing the simulation: the history is the same
##                          with extraction as without it.
##   spoiler_problems(inv)  the investigator's view carries no truth: no event or belief ids, no audit fields.
##   provenance_problems    every statement goes back to a belief its speaker held by then (or is an audited lie by
##                          the person responsible), every trace and record line to a real event, every withheld
##                          thing stays out of the view, every verdict to the causal record.
## A candidate is not a case: whether a playable mystery can be made of it is Pilot 4B's question. Only an
## incident with someone genuinely responsible for a crime can ever qualify (case_builder.gd, eligibility).
extends RefCounted

const Simulation = preload("res://scripts/sim/simulation.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")
const SimRng = preload("res://scripts/sim/sim_rng.gd")
const Memory = preload("res://scripts/sim/sim_memory.gd")
const Incidents = preload("res://scripts/sim/sim_incidents.gd")
const CaseBuilder = preload("res://scripts/cases/case_builder.gd")
const CaseText = preload("res://scripts/cases/case_text.gd")

## Fields that belong to the sealed truth and must never appear in the investigator's view.
const FORBIDDEN_KEYS := ["intent", "causes", "status", "lie", "error", "implicates", "responsible", "event", "belief",
		"created_by", "supports", "accurate", "answer", "narrative", "chain", "guilty_of", "traits", "audit",
		"withheld_reason", "disclosure", "root", "segments", "true_segments", "true_text", "about_event", "eligibility",
		"motive", "mechanism", "victims", "verdict"]


static func collect(cfg: Dictionary, selected := "", check := false) -> Dictionary:
	## {"sim", "cases": {incident id: case}, "problems": {incident id: [problem]}}: the town run to its end, with
	## every case candidate (or only ``selected``) frozen at its case start, the end of the hour in which the
	## investigator arrives. With ``check``, each case's provenance is checked at that same instant (some beliefs,
	## like someone's presence at the pub, go on being extended afterwards).
	var sim = Simulation.new(cfg)
	var cases := {}
	var problems := {}
	if not sim.ok:
		return {"sim": sim, "cases": cases, "problems": problems}
	var end: int = int(sim.config["days"]) * SimClock.DAY
	while sim.t < end:
		sim.step()
		for inc in sim.incidents:
			if inc["case_start"] == sim.t and Incidents.is_candidate(inc) and (selected == "" or inc["id"] == selected):
				cases[inc["id"]] = CaseBuilder.new(sim, inc).build()
				if check:
					problems[inc["id"]] = provenance_problems(sim, cases[inc["id"]])
	return {"sim": sim, "cases": cases, "problems": problems}


# ================================================================ the spoiler boundary
static func spoiler_problems(investigation: Dictionary) -> Array:
	var out := []
	var text := JSON.stringify(investigation)
	var ids := RegEx.new()
	ids.compile("\\b[EB]\\d{6}\\b")
	var m := ids.search(text)
	if m != null:
		out.append("investigation view contains an event or belief id (%s)" % m.get_string())
	var keys := {}
	_keys(investigation, keys)
	var leaked := []
	for k in FORBIDDEN_KEYS:
		if keys.has(k):
			leaked.append(k)
	if not leaked.is_empty():
		out.append("investigation view contains truth fields: %s" % ", ".join(PackedStringArray(leaked)))
	return out


static func _keys(obj, out: Dictionary) -> void:
	if obj is Dictionary:
		for k in obj:
			out[String(k)] = true
			_keys(obj[k], out)
	elif obj is Array:
		for v in obj:
			_keys(v, out)


# ================================================================ provenance
static func provenance_problems(sim, case_: Dictionary) -> Array:
	## Everything in the case comes from the simulated history up to the case start, through someone's own belief
	## or a real trace or record. Run at the case start, as collect(..., check = true) does.
	var out := []
	var inv: Dictionary = case_["investigation"]
	var truth: Dictionary = case_["truth"]
	var now: int = truth["case_start"]
	var inc: Dictionary = truth["incident"]
	var audit: Dictionary = truth["testimony_audit"]
	var responsible = inc["responsible"]
	var events: Dictionary = sim.events.by_id
	out.append_array(spoiler_problems(inv))
	# --- the incident and its chain
	if truth["answer"]["responsible"] != responsible:
		out.append("the answer names someone other than whoever was responsible")
	var chain_ids := {}
	for ev in truth["chain"]:
		chain_ids[ev["id"]] = true
		if int(ev["time"]) > now:
			out.append("chain event %s is after the case start" % ev["id"])
	if not chain_ids.has(inc["core_event"]):
		out.append("the chain leaves out the incident itself")
	var elig: Dictionary = case_["eligibility"]
	if elig["eligible"] and (responsible == null or not (inc["family"] in CaseBuilder.CRIME_FAMILIES)):
		out.append("eligible without anyone responsible for a crime")
	# --- every statement
	var visible_texts := {}
	for rid in inv["testimony"]:
		if not sim.residents[rid].alive and sim.residents[rid].death_event != "" \
				and int(events[sim.residents[rid].death_event]["time"]) <= now:
			out.append("%s speaks though dead by the case start" % rid)
		for it in inv["testimony"][rid]["items"]:
			var key: String = it["key"]
			visible_texts[rid + "|" + String(it["text"])] = true
			if not audit.has(key):
				out.append("%s: statement without an audit entry" % key)
				continue
			var a: Dictionary = audit[key]
			if a["speaker"] != rid:
				out.append("%s: audited for %s, said by %s" % [key, a["speaker"], rid])
			if a.get("summary", false):
				var members: Array = it.get("members", [])
				if members.size() < 2 or a["members"] != members:
					out.append("%s: a summary that does not stand for two or more statements" % key)
				for mk in members:
					if not audit.has(mk) or audit[mk].get("summary", false):
						out.append("%s: summary member %s is not a statement" % [key, mk])
				continue
			if a["status"] == "lie":
				out.append_array(_lie_problems(sim, key, rid, a, inc, responsible, now))
				continue
			if a.has("segments"):
				out.append_array(_account_problems(sim, key, rid, a["segments"]))
				continue
			if a["belief"] == null:
				out.append("%s: a truthful statement with no belief behind it" % key)
				continue
			out.append_array(_belief_problems(sim, case_, key, rid, it, a, now))
	# --- what was withheld stays out of the view
	for key in audit:
		if String(key).begins_with("W-"):
			var w: Dictionary = audit[key]
			if visible_texts.has(w["speaker"] + "|" + String(w["text"])) and w["withheld_reason"] == "self-protection":
				out.append("%s: withheld to protect themselves, yet in the view" % key)
			var b = sim.beliefs.get(w["belief"])
			if b == null or b["holder"] != w["speaker"] or int(b["acquired"]) > now:
				out.append("%s: withheld belief that is not the speaker's own by then" % key)
	# --- traces and records
	var traces := {}
	for p in inv["places"]:
		for t in p["traces"]:
			traces[t["id"]] = p["id"]
		if not p["allowed"] and not p["traces"].is_empty():
			out.append("traces shown at %s, where the investigator may not look" % p["id"])
	for v in inv["vehicles"]:
		for t in v["traces"]:
			traces[t["id"]] = v["id"]
		if not v["allowed"] and not v["traces"].is_empty():
			out.append("traces shown on %s, which the investigator may not look at" % v["id"])
	for tid in traces:
		var e = _evidence(sim, String(tid).substr(2))
		if e == null:
			out.append("%s: no such trace" % tid)
			continue
		if e["place"] != traces[tid] or not sim.world.present_at(e, now):
			out.append("%s: not at %s at the case start" % [tid, traces[tid]])
		if not events.has(e["created_by"]) or int(events[e["created_by"]]["time"]) > now:
			out.append("%s: not left by anything that happened by then" % tid)
		if not truth["evidence_audit"].has(tid) or truth["evidence_audit"][tid]["created_by"] != e["created_by"]:
			out.append("%s: not in the evidence audit" % tid)
	for e in sim.world.evidence:
		if not sim.world.present_at(e, now) and truth["evidence_audit"].has("T-" + String(e["id"])):
			out.append("T-%s: gone by the case start, yet in the evidence audit" % e["id"])
	for book in inv["records"]:
		for x in inv["records"][book]["entries"]:
			var rec = _record(sim, book, String(x["id"]).substr(2))
			if rec == null or int(rec["time"]) != int(x["time"]) or rec["text"] != x["text"]:
				out.append("%s: not a line of %s as written" % [x["id"], book])
				continue
			if int(rec["time"]) > now or not events.has(rec["event"]) or int(events[rec["event"]]["time"]) > int(rec["time"]):
				out.append("%s: written before what it records, or after the case start" % x["id"])
	# --- relevance verdicts come from the causal record
	var web := {}
	for e in truth["relevance_web"]:
		web[e] = true
	for ref in truth["relevance"]:
		var v: Dictionary = truth["relevance"][ref]
		if v["verdict"] == "connected" and not web.has(v["source"]):
			out.append("%s: connected to an event outside the incident's web" % ref)
	return out


static func _evidence(sim, id: String):
	for e in sim.world.evidence:
		if e["id"] == id:
			return e
	return null


static func _record(sim, book: String, id: String):
	for x in sim.world.records.get(book, []):
		if x["id"] == id:
			return x
	return null


static func _lie_problems(sim, key: String, rid: String, a: Dictionary, inc: Dictionary, responsible, now: int) -> Array:
	## A lie must have a reason in the history: the person responsible hiding where they were or explaining away the
	## damage, or someone who started a fight saying the other did.
	var out := []
	if a.get("error") == null or String(a["error"]) == "":
		out.append("%s: a lie without an explanation" % key)
	if a.has("segments"):
		if rid != responsible:
			out.append("%s: a false account of their movements by someone not responsible" % key)
		if not a.has("true_segments"):
			out.append("%s: a false account without the truth it hides" % key)
		else:
			out.append_array(_account_problems(sim, key, rid, a["true_segments"]))
	elif a["belief"] == null:
		if rid != responsible or a.get("about_event") != inc["core_event"]:
			out.append("%s: a made-up story that covers nothing of their own" % key)
	else:
		var b = sim.beliefs.get(a["belief"])
		if b == null or b["holder"] != rid or b["claim"]["kind"] != "assault" or b["claim"]["subject"] != rid \
				or int(b["acquired"]) > now:
			out.append("%s: a lie that is not about a fight they started" % key)
	return out


static func _account_problems(sim, key: String, rid: String, segs: Array) -> Array:
	## Someone's own account of where they were matches where the presence record puts them.
	var out := []
	for sg in segs:
		var s: int = sg[1]
		var last: int = maxi(s, int(sg[2]) - 1)
		for m in [s, last]:
			if sim.where(rid, m) != sg[0]:
				out.append("%s: says %s was at %s at %s, but the record has them at %s" % [key, rid, sg[0], SimClock.fmt(m),
						sim.where(rid, m)])
	return out


static func _belief_problems(sim, case_: Dictionary, key: String, rid: String, it: Dictionary, a: Dictionary, now: int) -> Array:
	## The statement is the speaker's own belief, held by the case start, told as they recall it now.
	var out := []
	var b = sim.beliefs.get(a["belief"])
	if b == null:
		return ["%s: no such belief %s" % [key, a["belief"]]]
	if b["holder"] != rid:
		out.append("%s: told by %s from %s's belief" % [key, rid, b["holder"]])
	if int(b["acquired"]) > now:
		out.append("%s: a belief formed after the case start" % key)
	if it["source"] != b["source"] or a["event"] != b["event"]:
		out.append("%s: not told as the belief came (%s, %s)" % [key, it["source"], b["source"]])
	var rec: Dictionary = Memory.recollect(b, now, SimRng.new([sim.config["seed"], "recall",
			CaseBuilder.recall_key(sim, case_["truth"]["incident"]), b["id"]]))
	var expected := CaseText.render(sim, rid, b, rec["claim"])
	if expected != it["text"]:
		out.append("%s: says \"%s\", but the belief, as recalled, reads \"%s\"" % [key, it["text"], expected])
	if a["status"] == "mistaken" and a.get("error") == null:
		out.append("%s: a mistake with no cause" % key)
	if b["claim"]["kind"] in ["theft_self", "stash"]:
		out.append("%s: a thief's own knowledge in the view" % key)
	return out


# ================================================================ statistics (compared with Python)
const FAMILIES := ["theft", "accounting_error", "assault", "collision", "fall"]
const SOURCES := ["self", "saw", "heard", "told", "inferred"]
const STATUSES := ["accurate", "mistaken", "lie", "unverifiable"]
const VERDICT_GROUPS := ["statement", "trace", "record"]
const SUPPORTS := ["places_responsible", "act", "motive", "vehicle", "sudden_money", "absence", "suspicion_correct",
		"misleading", "responsible_lie", "mechanism"]


static func stats(cases: Array, months: int) -> Dictionary:
	## What the cases hold, measured exactly as tools/case_reference.py measures Python's.
	var n := cases.size()
	var out := {"cases": float(n), "per_month.candidates": n / float(maxi(1, months))}
	for fam in FAMILIES:
		var k := 0
		for c in cases:
			if c["truth"]["incident"]["family"] == fam:
				k += 1
		out["share.family." + fam] = k / float(maxi(1, n))
	var elig := 0
	for c in cases:
		if c["eligibility"]["eligible"]:
			elig += 1
	out["share.eligible"] = elig / float(maxi(1, n))
	var sums := {"statements": 0.0, "per_resident": 0.0, "summaries": 0.0, "withheld": 0.0, "guarded": 0.0, "lies": 0.0,
			"evasive": 0.0, "traces_visible": 0.0, "traces_present": 0.0, "records_visible": 0.0, "places_refused": 0.0}
	var sources := {}
	var statuses := {}
	var verdicts := {}
	var groups := {}
	var with_support := {}
	var told := 0
	for c in cases:
		var inv: Dictionary = c["investigation"]
		var truth: Dictionary = c["truth"]
		var audit: Dictionary = truth["testimony_audit"]
		var alive := 0
		var present := {}
		var statements := 0
		for rid in inv["testimony"]:
			var t: Dictionary = inv["testimony"][rid]
			alive += 1
			if not Array(t["evasive_topics"]).is_empty():
				sums["evasive"] += 1
			for it in t["items"]:
				statements += 1
				var a: Dictionary = audit[it["key"]]
				if a.get("summary", false):
					sums["summaries"] += 1
					continue
				sources[it["source"]] = int(sources.get(it["source"], 0)) + 1
				statuses[a["status"]] = int(statuses.get(a["status"], 0)) + 1
				told += 1
				if it["guarded"]:
					sums["guarded"] += 1
				if a.get("lie", false):
					sums["lies"] += 1
				for sp in a.get("supports", []):
					present[sp] = true
		sums["statements"] += statements
		sums["per_resident"] += statements / float(maxi(1, alive))
		for k in audit:
			if String(k).begins_with("W-"):
				sums["withheld"] += 1
		for p in inv["places"]:
			sums["traces_visible"] += p["traces"].size()
			if not p["allowed"]:
				sums["places_refused"] += 1
		for v in inv["vehicles"]:
			sums["traces_visible"] += v["traces"].size()
		sums["traces_present"] += truth["evidence_audit"].size()
		for book in inv["records"]:
			sums["records_visible"] += inv["records"][book]["entries"].size()
		for sp in present:
			with_support[sp] = int(with_support.get(sp, 0)) + 1
		for ref in truth["relevance"]:
			var g := "statement"
			if String(ref).begins_with("T-"):
				g = "trace"
			elif String(ref).begins_with("R-"):
				g = "record"
			groups[g] = int(groups.get(g, 0)) + 1
			var gv: String = g + "." + String(truth["relevance"][ref]["verdict"])
			verdicts[gv] = int(verdicts.get(gv, 0)) + 1
	for k in sums:
		out["per_case." + k] = sums[k] / float(maxi(1, n))
	for s in SOURCES:
		out["share.source." + s] = int(sources.get(s, 0)) / float(maxi(1, told))
	for s in STATUSES:
		out["share.status." + s] = int(statuses.get(s, 0)) / float(maxi(1, told))
	for g in VERDICT_GROUPS:
		for v in ["connected", "unrelated", "uncertain"]:
			out["share.verdict.%s.%s" % [g, v]] = int(verdicts.get(g + "." + v, 0)) / float(maxi(1, int(groups.get(g, 0))))
	for s in SUPPORTS:
		out["share.cases_with." + s] = int(with_support.get(s, 0)) / float(maxi(1, n))
	return out
