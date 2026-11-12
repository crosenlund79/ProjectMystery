## Scoring a theory and building the reveal: a port of mystery/investigate/verdict.py.
##
## This is the only script that opens the sealed truth, and only once the investigation is
## concluded (a theory was submitted, or the player gave up). ``unseal_count`` lets tests prove
## the seal stayed shut during play.
extends RefCounted

const Clock = preload("res://scripts/core/clock.gd")
const CaseFormat = preload("res://scripts/core/case_format.gd")

static var unseal_count := 0


const MISTAKES := {
	"time_distorted": "had the time wrong",
	"misremembered_time": "misremembered the time",
	"misidentified": "mistook someone else for them",
	"wrong suspect": "suspected the wrong person",
	"mistaken_inference": "drew the wrong conclusion",
}


static func mistake_words(error) -> String:
	var e := String(error) if error != null and String(error) != "" else "wrong"
	if e.begins_with("partly wrong: "):
		var rest := e.substr(14)
		return "partly wrong: " + String(MISTAKES.get(rest, rest.replace("_", " ")))
	return String(MISTAKES.get(e, e.replace("_", " ")))


static func _explain_contradictions(inv, truth: Dictionary, names: Dictionary) -> Array:
	## What really lay behind each contradiction on the player's timeline (verdict.explain_contradictions).
	var out := []
	for c in inv.timeline()["contradictions"]:
		if c["kind"] == "approximate":
			continue
		var parts := PackedStringArray()
		var statuses := []
		var errors := []
		for eid in [c["a"], c["b"]]:
			var e: Dictionary = inv.entry(String(eid))
			var a = truth["testimony_audit"].get(e.get("ref"))
			if a == null:
				parts.append("%s is a written record." % eid)
				statuses.append("accurate")
				continue
			statuses.append(a["status"])
			if a["status"] == "lie":
				var why = a.get("error")
				parts.append("%s was a lie: %s." % [eid, why if why != null and String(why) != "" else "deliberately false"])
			elif a["status"] == "mistaken":
				errors.append(String(a.get("error")) if a.get("error") != null else "")
				parts.append("%s was mistaken: %s." % [eid, mistake_words(a.get("error"))])
			else:
				parts.append("%s was true." % eid)
		var really := "both true"
		var misidentified := false
		for err in errors:
			if String(err).ends_with("misidentified"):
				misidentified = true
		if statuses.has("lie"):
			really = "lie"
		elif misidentified:
			really = "mistaken identity"
		elif statuses.has("mistaken"):
			really = "honest mistake"
		else:
			parts = PackedStringArray(["Both were true: the times were only approximate."])
		out.append({"a": c["a"], "b": c["b"], "who": names.get(c["who"], c["who"]), "kind": c["kind"],
				"really": really, "explanation": " ".join(parts)})
	return out


static func reveal(inv) -> Dictionary:
	if not inv.state["concluded"]:
		return {"op": "reveal", "sealed": true, "model": null}
	unseal_count += 1
	var opened := CaseFormat.unseal(inv.package["sealed_truth"], inv.case_id)
	if not opened["ok"]:
		return {"op": "reveal", "sealed": true, "model": null, "error": opened["error"]}
	var truth: Dictionary = opened["truth"]
	var theory = inv.state.get("theory")
	if theory != null:
		var refs := []
		for eid in theory.get("cites", []):
			var e: Dictionary = inv.entry(eid)
			if not e.is_empty() and e.get("ref") != null:
				refs.append(e["ref"])
		theory = theory.duplicate(true)
		theory["cite_refs"] = refs
	var result := score(truth, theory, int(inv.state.get("hint_spend", 0)))
	inv.state["revealed"] = true
	inv.state["score"] = result
	return {"op": "reveal", "sealed": false, "model": _model(inv, truth, theory, result)}


static func _label(options: Array, id) -> String:
	for o in options:
		if o["id"] == id:
			return o["label"]
	return str(id)


static func score(truth: Dictionary, theory, hint_spend: int) -> Dictionary:
	## {"total": int, "parts": [[name, points], ...], "notes": [...]} - score() in Python.
	var ans: Dictionary = truth["answer"]
	var verdict: String = truth["suitability"]["verdict"]
	var parts := []
	var notes := []
	if theory == null:
		parts.append(["no theory", 0])
		notes.append("You gave up without a theory.")
	elif theory["mechanism"] == "unresolved":
		var caution := verdict == "ambiguous" or verdict == "unsolvable"
		parts.append(["cautious verdict", 50 if caution else 15])
		notes.append("Calling it unresolved was reasonable: the evidence really was thin." if caution else
				"There was enough evidence to say more than 'unresolved'.")
	else:
		parts.append(["explanation", 40 if theory["mechanism"] == ans["mechanism"] else 0])
		parts.append(["responsibility", 30 if theory["responsible"] == ans["responsible"] else 0])
		var motive_ok := false
		if ans["responsible"] == null:
			motive_ok = theory["motive"] == "none" or theory["motive"] == "unknown"
		else:
			motive_ok = ans["motives"].has(theory["motive"])
		parts.append(["motive", 10 if motive_ok else 0])
		if theory["responsible"] != null and theory["responsible"] != ans["responsible"]:
			notes.append("You named the wrong person. In a real town that would have consequences.")
	var cites := _cites(truth, theory)
	parts.append(["evidence cited", cites[0]])
	notes.append_array(cites[1])
	parts.append(["hints", -5 * hint_spend])
	var total := 0
	for part in parts:
		total += int(part[1])
	return {"total": clampi(total, 0, 100), "parts": parts, "notes": notes}


static func _cites(truth: Dictionary, theory) -> Array:
	if theory == null or theory.get("cite_refs", []).is_empty():
		return [0, []]
	var good := 0
	var bad := 0
	var chain_ids := {}
	for e in truth["chain"]:
		chain_ids[e["id"]] = true
	for ref in theory["cite_refs"]:
		var a = truth["testimony_audit"].get(ref)
		if a == null:
			a = truth["evidence_audit"].get(ref)
		if a == null:
			a = truth["record_audit"].get(ref)
		if a == null:
			continue
		if String(ref).begins_with("K"):
			var liar_exposed: bool = a["status"] == "lie" and a["speaker"] == truth["answer"]["responsible"]
			var supports = a.get("supports", [])
			if (a["status"] == "accurate" and supports != null and not supports.is_empty()) or liar_exposed:
				good += 1
			elif a["status"] == "mistaken" or a["status"] == "lie":
				bad += 1
		elif chain_ids.has(a.get("created_by")) or chain_ids.has(a.get("event")) \
				or ["ledger_error", "drink", "repair", "treated"].has(a.get("event_kind")):
			good += 1
	var notes := []
	if bad > 0:
		notes.append("%d of the statements you relied on were mistaken or lies." % bad)
	return [mini(20, 5 * good) - 3 * bad, notes]


static func _event_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a["time"]) != int(b["time"]):
		return int(a["time"]) < int(b["time"])
	return String(a["id"]) < String(b["id"])


static func _sorted_events(events: Array) -> Array:
	## Stable merge sort by (time, id), like Python's sorted().
	if events.size() <= 1:
		return events.duplicate()
	var mid: int = events.size() >> 1
	var left := _sorted_events(events.slice(0, mid))
	var right := _sorted_events(events.slice(mid))
	var out := []
	var i := 0
	var j := 0
	while i < left.size() and j < right.size():
		if _event_less(right[j], left[i]):
			out.append(right[j])
			j += 1
		else:
			out.append(left[i])
			i += 1
	while i < left.size():
		out.append(left[i])
		i += 1
	while j < right.size():
		out.append(right[j])
		j += 1
	return out


static func _model(inv, truth: Dictionary, theory, result: Dictionary) -> Dictionary:
	var names := {}
	for rid in truth["private_states"]:
		names[rid] = truth["private_states"][rid]["name"]
	var mechs: Array = inv.mechanisms()
	var motive_opts: Array = inv.motives()
	var ans: Dictionary = truth["answer"]
	var motive_labels := []
	for m in ans["motives"]:
		motive_labels.append(_label(motive_opts, m))
	var model := {
		"narrative": truth["narrative"],
		"answer": {"mechanism": _label(mechs, ans["mechanism"]),
				"responsible": names.get(ans["responsible"], "no one") if ans["responsible"] != null else "no one",
				"outcome": String(ans["outcome"]).replace("_", " "), "motives": motive_labels},
		"theory": null,
		"score": {"total": result["total"], "parts": result["parts"], "notes": result["notes"]},
		"timeline": [], "annotations": [], "plain_true": 0, "missed": [], "assessment": "",
	}
	if theory != null:
		model["theory"] = {"mechanism": _label(mechs, theory["mechanism"]),
				"responsible": names.get(theory["responsible"], "no one") if theory["responsible"] != null else "no one",
				"motive": _label(motive_opts, theory["motive"])}
	var events := []
	for ev in truth["chain"]:
		events.append(ev)
	for ev in truth["responsible_movements"]:
		events.append(ev)
	events = _sorted_events(events)
	var seen := {}
	for ev in events:
		if seen.has(ev["id"]) or ev["kind"] == "meal":
			continue
		seen[ev["id"]] = true
		model["timeline"].append({"time": int(ev["time"]), "label": Clock.fmt(ev["time"]), "summary": ev["summary"]})
	var cited := {}
	if theory != null:
		for c in theory.get("cites", []):
			cited[c] = true
	var audit: Dictionary = truth["testimony_audit"]
	for e in inv.state["entries"]:
		var ref = e.get("ref")
		var verdict := ""
		if ref != null and audit.has(ref) and (audit[ref]["status"] == "accurate" or audit[ref]["status"] == "unverifiable") \
				and not cited.has(e["id"]) and (audit[ref].get("supports") == null or audit[ref]["supports"].is_empty()):
			model["plain_true"] += 1
			continue
		if ref != null and audit.has(ref):
			var a: Dictionary = audit[ref]
			if a["status"] == "lie":
				var why = a.get("error")
				verdict = "LIE — %s" % (why if why else "deliberately false")
				if a.get("true_text"):
					verdict += ". Really: %s" % a["true_text"]
			elif a["status"] == "mistaken":
				var why = a.get("error")
				verdict = "MISTAKEN — %s" % String(why if why else "wrong").replace("_", " ")
			elif a["status"] == "unverifiable":
				verdict = "true as far as it goes (they couldn't tell who)"
			else:
				verdict = "true"
		elif ref != null and truth["evidence_audit"].has(ref):
			verdict = "left by: %s" % truth["evidence_audit"][ref]["event_summary"]
		elif ref != null and truth["record_audit"].has(ref):
			verdict = "records: %s" % truth["record_audit"][ref]["event_summary"]
		if verdict != "":
			model["annotations"].append({"entry": e["id"], "text": e["text"], "verdict": verdict,
					"cited": cited.has(e["id"])})
	model["contradictions"] = _explain_contradictions(inv, truth, names)
	var found := {}
	for e in inv.state["entries"]:
		found[e.get("ref")] = true
		if e.get("ref") != null:
			# a summary you heard counts for the statements it stands for
			for m in inv.item(String(e["ref"])).get("members", []):
				found[m] = true
	var place_names: Dictionary = truth.get("place_names", {})
	for ch in truth["suitability"]["channels"]:
		if ch["strength"] != "strong" and ch["strength"] != "hearsay":
			continue
		var hit := false
		for k in ch["keys"]:
			if found.has(k):
				hit = true
		if hit:
			continue
		var src = names.get(ch["source"])
		if not src:
			src = place_names.get(ch["source"], ch["source"])
		model["missed"].append({"type": ch["type"], "source": src, "needs_pressing": bool(ch.get("needs_pressing", false))})
	var s: Dictionary = truth["suitability"]
	model["assessment"] = "%s — %d independent channel(s), %d source(s) of misleading information, %d lie(s) by the person responsible." % [
			s["verdict"], int(s["independent_channels"]), int(s["red_herrings"]), int(s["lies_by_responsible"])]
	return model
