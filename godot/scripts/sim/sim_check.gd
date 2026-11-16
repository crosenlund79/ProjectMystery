## Integrity checks and summary statistics for a simulation run, used by tests/test_sim.gd and the demo
## (tests/run_sim.gd). The statistics use exactly the definitions in tools/sim_reference.py, which measures
## the Python simulation the same way.
extends RefCounted

const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Crime = preload("res://scripts/sim/sim_crime.gd")
const Incidents = preload("res://scripts/sim/sim_incidents.gd")

const DAY := 1440
const MEMORY_KINDS := ["presence", "sighting", "intoxicated", "noise", "debt", "refusal", "hardship", "argument",
		"grudge", "rent_missed", "loan", "help", "reconcile", "purchase", "laid_off", "suspect", "loss", "damage",
		"theft_self", "stash", "confession"]
const ERRORS := ["misidentified", "time_distorted", "certainty_inflated"]
const SPREAD := {"argument": ["argument"], "refusal": ["loan_refused", "credit_refused"], "rent_missed": ["rent_missed"],
		"loss": ["loss_discovered"]}
## Events only the crime layer makes (Pilot 3A).
const CRIME_EVENTS := ["theft", "theft_aborted", "forced_entry", "hide_loot", "stash_withdraw", "ledger_error",
		"loss_discovered", "cleaned_up", "confession"]
const COMPARED_KINDS := ["move", "meal", "pub_meal", "drink", "purchase", "credit", "credit_refused", "wage",
		"rent_paid", "rent_missed", "loan", "loan_refused", "repay", "help", "reconcile", "argument", "debt_overdue",
		"deposit", "withdraw", "chat"]


static func problems(sim) -> Array:
	## Everything wrong with a finished run; empty when every rule held.
	var out := []
	out.append_array(sim.errors)
	if not sim.ok:
		return out
	_check_money(sim, out)
	_check_events(sim, out)
	_check_presence(sim, out)
	_check_people(sim, out)
	_check_debts(sim, out)
	_check_memory(sim, out)
	_check_crime(sim, out)
	return out


static func _check_money(sim, out: Array) -> void:
	## Replay every transfer from the starting balances: nothing may go negative on the way, and the replay
	## must end exactly where the world is. Money and food only enter or leave through "outside" and "eaten".
	var bal: Dictionary = sim.initial_balances.duplicate(true)
	var came_in := {"cash": 0, "food": 0}
	var went_out := {"cash": 0, "food": 0}
	for tr in sim.world.transfers:
		var asset: String = tr["asset"]
		if tr["amount"] <= 0:
			out.append("transfer of %d %s for %s" % [tr["amount"], asset, tr["event"]])
		if bal.has(tr["src"]):
			bal[tr["src"]][asset] -= tr["amount"]
			if bal[tr["src"]][asset] < 0:
				out.append("%s went below zero %s at %s" % [tr["src"], asset, SimClock.fmt(tr["time"])])
		elif tr["src"] == "outside":
			came_in[asset] += tr["amount"]
		else:
			out.append("transfer from unknown account %s" % tr["src"])
		if bal.has(tr["dst"]):
			bal[tr["dst"]][asset] += tr["amount"]
		elif tr["dst"] == "outside" or tr["dst"] == "eaten":
			went_out[asset] += tr["amount"]
		else:
			out.append("transfer to unknown account %s" % tr["dst"])
		var ev: Dictionary = sim.events.by_id.get(tr["event"], {})
		if ev.is_empty():
			out.append("transfer for unknown event %s" % tr["event"])
		elif ev["time"] != tr["time"]:
			out.append("transfer at %s for %s, which happened at %s" % [SimClock.fmt(tr["time"]), tr["event"],
					SimClock.fmt(ev["time"])])
	var now: Dictionary = sim.balances()
	for acct in now:
		for asset in ["cash", "food"]:
			if not bal.has(acct) or bal[acct][asset] != now[acct][asset]:
				out.append("%s holds %d %s, but its transfers add up to %s" % [acct, now[acct][asset], asset,
						str(bal.get(acct, {}).get(asset, "nothing"))])
	for asset in ["cash", "food"]:
		var start := 0
		var end := 0
		for acct in now:
			start += int(sim.initial_balances[acct][asset])
			end += int(now[acct][asset])
		if start + came_in[asset] - went_out[asset] != end:
			out.append("%s is not conserved: %d + %d in - %d out != %d" % [asset, start, came_in[asset],
					went_out[asset], end])
	for cid in sim.world.containers:
		# every till, tin and pantry holds what its owners expect, short only by what was stolen from it or
		# written into its books twice since it was last counted
		var c: Dictionary = sim.world.containers[cid]
		var explained: Array = Crime.unexplained_shortfall(sim, c) if sim.crime_on else [0, 0]
		if c["expected_cash"] - c["cash"] != explained[0] or c["expected_food"] - c["food"] != explained[1]:
			out.append("%s holds %d cash and %d food; its owners expect %d and %d (unseen: %s)" % [c["label"], c["cash"],
					c["food"], c["expected_cash"], c["expected_food"], explained])


static func _check_events(sim, out: Array) -> void:
	var last := -1
	var seen := {}
	for ev in sim.events.events:
		var id: String = ev["id"]
		if seen.has(id):
			out.append("event id %s used twice" % id)
		seen[id] = true
		if ev["time"] < last:
			out.append("%s at %s is logged after an event at %s" % [id, SimClock.fmt(ev["time"]), SimClock.fmt(last)])
		last = ev["time"]
		if ev["time"] < 0 or ev["time"] >= maxi(sim.t, 1):
			out.append("%s happens outside the simulated time (%d)" % [id, ev["time"]])
		var where: String = ev["location"]
		if where == "-":
			if not String(ev["kind"]).begins_with("prior_"):
				out.append("%s (%s) has no place" % [id, ev["kind"]])
		elif not sim.world.locations.has(where):
			out.append("%s happens at unknown place %s" % [id, where])
		for who in ev["actors"] + ev["targets"]:
			if not sim.residents.has(who):
				out.append("%s involves unknown person %s" % [id, who])
		for c in ev["causes"]:
			var cause: Dictionary = sim.events.by_id.get(c, {})
			if cause.is_empty():
				out.append("%s is caused by unknown event %s" % [id, c])
			elif cause["time"] > ev["time"] or cause["seq"] >= ev["seq"]:
				out.append("%s is caused by %s, which comes after it" % [id, c])
		if ev["kind"] == "move":
			var path: Array = ev["data"]["path"]
			var times: Array = ev["data"]["times"]
			for i in range(path.size() - 1):
				if not sim.world.locations[path[i]]["adj"].has(path[i + 1]):
					out.append("%s walks from %s to %s, which are not connected" % [id, path[i], path[i + 1]])
				if times[i + 1] <= times[i]:
					out.append("%s arrives before it leaves" % id)


static func _check_presence(sim, out: Array) -> void:
	for rid in sim.ids:
		var ivs: Array = sim.intervals[rid]
		if ivs[0][1] != 0:
			out.append("%s's whereabouts do not start at the beginning" % rid)
		for i in ivs.size():
			var iv: Array = ivs[i]
			if not sim.world.locations.has(iv[0]):
				out.append("%s is at unknown place %s" % [rid, iv[0]])
			if i + 1 < ivs.size():
				if iv[2] != ivs[i + 1][1]:
					out.append("%s has a gap in their whereabouts at %s" % [rid, SimClock.fmt(iv[1])])
				if iv[2] < iv[1]:
					out.append("%s leaves %s before arriving" % [rid, iv[0]])
				if not sim.world.locations[iv[0]]["adj"].has(ivs[i + 1][0]):
					out.append("%s jumps from %s to %s" % [rid, iv[0], ivs[i + 1][0]])
			elif iv[2] != -1:
				out.append("%s's last whereabouts are closed" % rid)
	for vid in sim.world.vehicles:
		if not sim.world.locations.has(sim.world.vehicles[vid]["location"]):
			out.append("%s is at an unknown place" % vid)


static func _check_people(sim, out: Array) -> void:
	for rid in sim.ids:
		var r = sim.residents[rid]
		for need in ["hunger", "energy", "social", "stress", "intox"]:
			var v: float = r.get(need)
			if v < 0.0 or v > 100.0:
				out.append("%s's %s is %s" % [rid, need, v])
		if r.cash < 0:
			out.append("%s has %d crowns" % [rid, r.cash])
		for k in r.traits:
			if r.traits[k] < 0.0 or r.traits[k] > 1.0:
				out.append("%s's %s is %s" % [rid, k, r.traits[k]])
		for other in r.rel:
			for k in r.rel[other]:
				if r.rel[other][k] < 0.0 or r.rel[other][k] > 1.0:
					out.append("%s's %s towards %s is %s" % [rid, k, other, r.rel[other][k]])
		if r.asleep and sim.loc(rid) != r.home:
			out.append("%s is asleep away from home, at %s" % [rid, sim.loc(rid)])
		if r.employed != (r.workplace != ""):
			out.append("%s is %s but has workplace '%s'" % [rid, "employed" if r.employed else "jobless", r.workplace])


static func _check_debts(sim, out: Array) -> void:
	for d in sim.world.debts:
		if not sim.residents.has(d["debtor"]) or not sim.residents.has(d["creditor"]) or d["debtor"] == d["creditor"]:
			out.append("%s is between %s and %s" % [d["id"], d["debtor"], d["creditor"]])
		if d["amount"] <= 0:
			out.append("%s is for %d" % [d["id"], d["amount"]])
		if not sim.events.by_id.has(d["origin_event"]):
			out.append("%s has no origin event" % d["id"])
		if d["settled"] >= 0:
			var ev: Dictionary = sim.events.by_id.get(d["settled_event"], {})
			if ev.is_empty() or ev["kind"] != "repay" or ev["data"].get("debt", "") != d["id"]:
				out.append("%s is settled without a repayment" % d["id"])
		elif d["settled_event"] != "":
			out.append("%s is open but has a repayment" % d["id"])


static func involved(rid: String, ev: Dictionary) -> bool:
	## A party to the event: who did it, to whom, or whom it names (the creditor, the landlord, the worker).
	if rid in ev["actors"] or rid in ev["targets"]:
		return true
	for v in ev["data"].values():
		if v is String and v == rid:
			return true
	return false


static func _check_memory(sim, out: Array) -> void:
	## No resident knows anything without a plausible source, and what was told stays told:
	##   self      they took part in the event it is about
	##   saw       they were at that place at that minute (the claim's place, or the event's)
	##   heard     they were within earshot: the same place, or as many steps away as the event was loud
	##   told      someone else said it, in a conversation the two of them had at that minute (a chat, or an
	##             accusation to their face), copied from what the speaker believed at the time; or, for the
	##             town's past, by a party to an old grudge or debt at the start
	##   inferred  drawn from their own beliefs, held before
	## Distortions follow the same rules: a misidentification happens only to an eye or ear witness (or is
	## passed on), a time or certainty only drifts in the telling. A sighting with no error names the person
	## who really passed.
	if not sim.memory_on:
		if not sim.beliefs.is_empty():
			out.append("memory is off but %d beliefs exist" % sim.beliefs.size())
		return
	for bid in sim.beliefs:
		var b: Dictionary = sim.beliefs[bid]
		var holder: String = b["holder"]
		var c: Dictionary = b["claim"]
		var label := "%s (%s %s a %s)" % [bid, holder, b["source"], c["kind"]]
		var ev = sim.events.by_id.get(b["event"]) if b["event"] else null
		if b["acquired"] < 0 or b["acquired"] >= maxi(sim.t, 1):
			out.append("%s was formed outside the simulated time" % label)
		if b["confidence"] < 0.0 or b["confidence"] > 1.0:
			out.append("%s has confidence %s" % [label, b["confidence"]])
		match b["source"]:
			"self":
				if ev == null or not involved(holder, ev):
					out.append("%s: first-hand knowledge of something they took no part in" % label)
			"saw":
				var place = c["location"] if c["location"] else (ev["location"] if ev != null else null)
				var was: String = sim.where(holder, b["acquired"])
				if place == null or was != place:
					out.append("%s: saw something at %s while at '%s'" % [label, place, was])
				if ev != null and ev["kind"] == "move" and c["kind"] == "sighting" and c["subject"] != null:
					var mover: String = ev["actors"][0]
					if b["error"] == "misidentified" and c["subject"] == mover:
						out.append("%s: marked misidentified but names the right person" % label)
					if b["error"] == null and c["subject"] != mover:
						out.append("%s: names %s, but %s passed" % [label, c["subject"], mover])
			"heard":
				var place = c["location"] if c["location"] else (ev["location"] if ev != null else null)
				var was: String = sim.where(holder, b["acquired"])
				var reach := 0
				if ev != null and ev["kind"] != "move":
					reach = maxi(0, int(ev["audibility"]) - 1)
				if place == null or was == "" or sim.world.hops(was, place) > reach:
					out.append("%s: heard something at %s from '%s'" % [label, place, was])
			"told":
				var by = b["told_by"]
				if by == null or by == holder or not sim.residents.has(by):
					out.append("%s: told by nobody" % label)
				elif b["via"] == null:
					if not (b["acquired"] == 0 and ev != null and String(ev["kind"]).begins_with("prior_") and involved(by, ev)):
						out.append("%s: told without a source belief" % label)
				else:
					var via = sim.beliefs.get(b["via"])
					if via == null or via["holder"] != by or via["acquired"] > b["acquired"]:
						out.append("%s: the teller did not believe it first" % label)
					if (ev == null or not (ev["kind"] in ["chat", "argument"]) or ev["time"] != b["acquired"]
							or not involved(holder, ev) or not involved(by, ev)):
						out.append("%s: told outside any conversation between %s and %s" % [label, by, holder])
					if via != null:
						for k in ["kind", "subject", "other", "location", "detail", "amount", "obj"]:
							if via["claim"]["kind"] != "suspect" and via["claim"][k] != c[k]:
								out.append("%s: %s changed in the telling" % [label, k])
			"inferred":
				if b["premises"].is_empty():
					out.append("%s: inferred from nothing" % label)
				for pid in b["premises"]:
					var pb = sim.beliefs.get(pid)
					if pb == null or pb["holder"] != holder or pb["acquired"] > b["acquired"]:
						out.append("%s: inferred from a belief they did not hold" % label)
			_:
				out.append("%s: unknown source" % label)
		if b["error"] in ["time_distorted", "certainty_inflated"] and b["source"] != "told":
			out.append("%s: %s without being told" % [label, b["error"]])
		if b["error"] == "misidentified" and not (b["source"] in ["saw", "heard", "told"]):
			out.append("%s: misidentified without seeing or hearing" % label)


static func _check_crime(sim, out: Array) -> void:
	## The crime layer keeps the same rules as everything else, and these besides:
	##   a theft takes from a container nobody else was at, into the thief's own stash, and is in the registry
	##   with the thief responsible; only the thief ever spends from or hides a stash, and stolen money leaves
	##   it only to be spent by them or handed back in a confession
	##   a discovered loss is exactly what was stolen and written in twice since the last count, by the events
	##   that did it, inside its window; an incident is discovered by the one who counted, after it happened
	##   a trace exists only because an event made it, there and then; it is cleared away by a later event;
	##   whoever noticed it was there to see it, and nobody "notices" a trace of their own wrongdoing
	##   nobody knows of a theft because it happened: only the thief holds anything that comes from the theft
	##   itself; everyone else learns of a loss from a count (seen, or told by someone who knew), and whom they
	##   suspect is inferred from a loss or damage they already knew of; a thief never goes looking for the
	##   culprit of their own theft
	if not sim.crime_on:
		if not sim.incidents.is_empty() or not sim.world.evidence.is_empty():
			out.append("crime is off but there are %d incidents and %d traces" % [sim.incidents.size(),
					sim.world.evidence.size()])
		for ev in sim.events.events:
			if ev["kind"] in CRIME_EVENTS or ev.has("discreet"):
				out.append("crime is off but %s is a %s" % [ev["id"], ev["kind"]])
				break
		return
	var by_event := {}  # event id -> transfers made for it
	for tr in sim.world.transfers:
		if not by_event.has(tr["event"]):
			by_event[tr["event"]] = []
		by_event[tr["event"]].append(tr)
		for side in ["src", "dst"]:
			var acct: String = tr[side]
			if not acct.begins_with("box:stash:"):
				continue
			var owner := acct.substr(10)
			var why: Dictionary = sim.events.by_id.get(tr["event"], {})
			var allowed := ["theft"] if side == "dst" else ["stash_withdraw", "hide_loot", "confession"]
			if why.is_empty() or not (why["kind"] in allowed) or not (owner in why["actors"]):
				out.append("%s's stash: %s %s for %s" % [owner, "filled" if side == "dst" else "emptied",
						tr["amount"], why.get("kind", tr["event"])])
	for ev in sim.events.events:
		var id: String = ev["id"]
		match ev["kind"]:
			"theft":
				var thief: String = ev["actors"][0]
				var cid: String = ev["objects"][0]
				for x in sim.ids:
					if x != thief and sim.where(x, ev["time"] - 2) == ev["location"]:
						out.append("%s: %s stole with %s there" % [id, thief, x])
				var moved: Array = by_event.get(id, [])
				if (moved.size() != 1 or moved[0]["src"] != "box:" + cid or moved[0]["dst"] != "box:stash:" + thief
						or moved[0]["amount"] != ev["data"]["amount"] or moved[0]["asset"] != ev["data"]["asset"]):
					out.append("%s: the loot did not go from %s into %s's stash" % [id, cid, thief])
				var inc: Dictionary = Incidents.incident_for(sim, id)
				if (inc.is_empty() or inc["core_event"] != id or inc["family"] != "theft" or inc["responsible"] != thief
						or inc["time"] != ev["time"] or inc["location"] != ev["location"]):
					out.append("%s: not registered as %s's theft" % [id, thief])
				if not (id in sim.residents[thief].guilty_of):
					out.append("%s: %s does not know they did it" % [id, thief])
			"ledger_error":
				var inc: Dictionary = Incidents.incident_for(sim, id)
				if inc.is_empty() or inc["family"] != "accounting_error" or inc["responsible"] != null:
					out.append("%s: a ledger mistake outside any accounting incident" % id)
				var sale: Dictionary = sim.events.by_id.get(ev["causes"][0], {}) if not ev["causes"].is_empty() else {}
				if sale.is_empty() or sale["kind"] != "purchase" or sale["data"]["paid"] != ev["data"]["amount"]:
					out.append("%s: writes in twice a sale that did not happen" % id)
			"loss_discovered":
				var cid: String = ev["objects"][0]
				var window: Array = ev["data"]["window"]
				var cash := 0
				var food := 0
				for cause in ev["causes"]:
					var ce: Dictionary = sim.events.by_id[cause]
					if not (ce["kind"] in ["theft", "ledger_error"]) or ce["objects"][0] != cid:
						out.append("%s: explained by %s, which did not touch %s" % [id, cause, cid])
					elif ce["time"] < window[0] or ce["time"] > ev["time"]:
						out.append("%s: explained by %s, outside its window" % [id, cause])
					elif ce["kind"] == "ledger_error" or ce["data"]["asset"] == "cash":
						cash += int(ce["data"]["amount"])
					else:
						food += int(ce["data"]["amount"])
				if cash != ev["data"]["cash"] or food != ev["data"]["food"]:
					out.append("%s: finds %d cash and %d food missing, but %d and %d went" % [id, ev["data"]["cash"],
							ev["data"]["food"], cash, food])
			"hide_loot":
				var thief: String = ev["actors"][0]
				var theft: Dictionary = sim.events.by_id.get(ev["causes"][0], {}) if not ev["causes"].is_empty() else {}
				if theft.is_empty() or theft["kind"] != "theft" or theft["actors"][0] != thief:
					out.append("%s: %s hides loot they did not take" % [id, thief])
				if ev["location"] != sim.residents[thief].home:
					out.append("%s: loot hidden away from home" % id)
			"confession":
				var culprit: String = ev["actors"][0]
				var core: String = ev["causes"][-1]
				var inc: Dictionary = Incidents.incident_for(sim, core)
				if not (core in sim.residents[culprit].guilty_of) or inc.is_empty() or not inc["reported_openly"]:
					out.append("%s: %s confesses to what they did not do" % [id, culprit])
	for e in sim.world.evidence:
		var src: Dictionary = sim.events.by_id.get(e["created_by"], {})
		if src.is_empty() or src["time"] != e["created_at"] or src["location"] != e["place"]:
			out.append("%s (%s) was not made by an event there and then" % [e["id"], e["kind"]])
			continue
		if e["removed_at"] >= 0:
			var gone: Dictionary = sim.events.by_id.get(e["removed_by"], {})
			if (gone.is_empty() or gone["kind"] != "cleaned_up" or gone["data"]["evidence"] != e["id"]
					or gone["time"] != e["removed_at"] or gone["location"] != e["place"] or gone["time"] < e["created_at"]):
				out.append("%s was removed without being cleared away" % e["id"])
		for rid in e["noticed_by"]:
			if sim.perceived.get(rid + "|" + e["created_by"], "") != "trace":
				out.append("%s: %s noticed it without seeing it" % [e["id"], rid])
			if Crime.made_by(sim, rid, e):
				out.append("%s: %s \"noticed\" their own trace" % [e["id"], rid])
	for inc in sim.incidents:
		var core: Dictionary = sim.events.by_id.get(inc["core_event"], {})
		if core.is_empty() or core["time"] != inc["time"] or core["location"] != inc["location"]:
			out.append("%s: its core event is not what happened there and then" % inc["id"])
		for rel in inc["related_events"]:
			if not sim.events.by_id.has(rel):
				out.append("%s: linked to unknown event %s" % [inc["id"], rel])
		if inc["discovered_at"] != null:
			var found: Dictionary = sim.events.by_id.get(inc["discovery_event"], {})
			if (found.is_empty() or found["time"] != inc["discovered_at"] or found["actors"][0] != inc["discovered_by"]
					or inc["discovered_at"] < inc["time"]):
				out.append("%s: discovered by %s, but not by what they did" % [inc["id"], inc["discovered_by"]])
			# what was discovered happened inside the window: the theft itself; for a run of ledger mistakes
			# (one too small to notice is written off at a count, the next joins the same incident), one of them
			var w = inc["window"]
			var inside := false
			for eid in [inc["core_event"]] + inc["related_events"]:
				var ie: Dictionary = sim.events.by_id.get(eid, {})
				if (not ie.is_empty() and ie["kind"] in ["theft", "ledger_error"] and w != null and w[0] <= ie["time"]
						and ie["time"] <= w[1]):
					inside = true
			if not inside:
				out.append("%s: happened outside the window it was discovered in" % inc["id"])
	for rid in sim.ids:
		for g in sim.residents[rid].guilty_of:
			var ge: Dictionary = sim.events.by_id.get(g, {})
			if ge.is_empty() or not (rid in ge["actors"]):
				out.append("%s is guilty of %s, which they did not do" % [rid, g])
	for bid in sim.beliefs:
		var b: Dictionary = sim.beliefs[bid]
		var c: Dictionary = b["claim"]
		var label := "%s (%s %s a %s)" % [bid, b["holder"], b["source"], c["kind"]]
		var root: Dictionary = _root(sim, b)
		var origin: Dictionary = sim.events.by_id.get(root["event"], {}) if root["event"] else {}
		if not origin.is_empty() and origin["kind"] in ["theft", "hide_loot", "stash_withdraw"] and not (b["holder"] in origin["actors"]):
			out.append("%s: knows of %s, which only %s knows of" % [label, origin["id"], origin["actors"][0]])
		match c["kind"]:
			"theft_self", "stash":
				if b["source"] != "self" or origin.is_empty() or not (b["holder"] in origin["actors"]):
					out.append("%s: a thief's secret held by someone else" % label)
			"loss":
				if origin.is_empty() or origin["kind"] != "loss_discovered":
					out.append("%s: knows of a loss nobody discovered" % label)
			"damage":
				if b["source"] == "saw":
					var trace := {}
					for e in sim.world.evidence:
						if e["created_by"] == b["event"] and e["place"] == c["location"]:
							trace = e
					# there to see when they saw it (whoever clears a trace away sees it as they do)
					if (trace.is_empty() or not (b["holder"] in trace["noticed_by"]) or b["acquired"] < trace["created_at"]
							or (trace["removed_at"] >= 0 and b["acquired"] > trace["removed_at"])):
						out.append("%s: saw damage that was not there to see" % label)
			"suspect":
				if b["source"] == "inferred":
					var first = sim.beliefs.get(b["premises"][0]) if not b["premises"].is_empty() else null
					if first == null or not (first["claim"]["kind"] in ["loss", "damage", "struck", "death"]):
						out.append("%s: a suspicion without a loss or damage behind it" % label)
					for g in sim.residents[b["holder"]].guilty_of:
						var ge: Dictionary = sim.events.by_id[g]
						var until: int = c["end"] if c["end"] != null else c["start"]
						if (ge["location"] == c["location"] and c["start"] - 60 <= ge["time"] and ge["time"] <= until + 60
								and ge["time"] <= b["acquired"]):
							out.append("%s: looks for the culprit of their own %s" % [label, g])


static func _root(sim, b: Dictionary) -> Dictionary:
	## The belief a piece of hearsay started from (follows ``via``).
	var seen := 0
	while b["via"] != null and sim.beliefs.has(b["via"]) and seen < 50:
		b = sim.beliefs[b["via"]]
		seen += 1
	return b


static func memory_stats(sim) -> Dictionary:
	## Beliefs per resident per day by source, kind and error; gossip; how far news of an argument, a refusal
	## or a missed rent spread (residents who weren't party to it and came to know); lenders' caution.
	## tools/sim_reference.py measures Python the same way. Undefined values are -1.
	var days: float = maxf(1.0, sim.t / float(DAY))
	var per := float(sim.ids.size()) * days
	var out := {}
	var by_source := {}
	var by_kind := {}
	var by_error := {}
	for bid in sim.beliefs:
		var b: Dictionary = sim.beliefs[bid]
		by_source[b["source"]] = int(by_source.get(b["source"], 0)) + 1
		by_kind[b["claim"]["kind"]] = int(by_kind.get(b["claim"]["kind"], 0)) + 1
		if b["error"]:
			by_error[b["error"]] = int(by_error.get(b["error"], 0)) + 1
	for src in ["self", "saw", "heard", "told", "inferred"]:
		out["belief_" + src] = by_source.get(src, 0) / per
	for k in MEMORY_KINDS:
		out["kind_" + k] = by_kind.get(k, 0) / per
	for e in ERRORS:
		out["error_" + e] = by_error.get(e, 0) / per
	var counts: Dictionary = sim.events.counts()
	out["gossip_chats"] = counts.get("chat", 0) / per
	out["gossip_transfers"] = int(sim.stats.get("gossip_transfers", 0)) / per
	out["suspicions"] = int(sim.stats.get("suspicions", 0)) / per
	var knowers := {}
	for bid in sim.beliefs:
		var b: Dictionary = sim.beliefs[bid]
		var root := _root(sim, b)
		if root["event"]:
			if not knowers.has(root["event"]):
				knowers[root["event"]] = {}
			knowers[root["event"]][b["holder"]] = true
	for name in SPREAD:
		var total := 0
		var n := 0
		for ev in sim.events.events:
			if ev["kind"] in SPREAD[name]:
				n += 1
				for h in knowers.get(ev["id"], {}):
					if not involved(h, ev):
						total += 1
		out["knowers_" + name] = float(total) / n if n > 0 else -1.0
	var lent: int = counts.get("loan", 0)
	var refused: int = counts.get("loan_refused", 0)
	out["loan_acceptance"] = float(lent) / (lent + refused) if lent + refused > 0 else -1.0
	return out


const CRIME_COUNTED := ["theft", "theft_aborted", "forced_entry", "ledger_error", "loss_discovered", "stash_withdraw",
		"confession", "cleaned_up"]


static func incident_at(sim, claim: Dictionary) -> Dictionary:
	## The incident (discovered or not) at a claim's place within six hours of its time, or {}: what a
	## suspicion is really about.
	if claim["start"] == null:
		return {}
	var until: int = claim["end"] if claim["end"] != null else claim["start"]
	for inc in sim.incidents:
		if inc["location"] == claim["location"] and claim["start"] - 6 * 60 <= inc["time"] and inc["time"] <= until + 6 * 60:
			return inc
	return {}


static func crime_stats(sim) -> Dictionary:
	## Crime-layer events per resident per day; the share of thefts discovered; the share of suspicions that fall
	## on whoever was really responsible (a ledger mistake has nobody); cash taken per theft of cash. Undefined
	## values are -1. tools/sim_reference.py measures Python the same way.
	var days: float = maxf(1.0, sim.t / float(DAY))
	var per := float(sim.ids.size()) * days
	var counts: Dictionary = sim.events.counts()
	var out := {}
	for k in CRIME_COUNTED:
		out[k] = counts.get(k, 0) / per
	var accusations := 0
	var taken := 0
	var cash_thefts := 0
	for ev in sim.events.events:
		if ev["kind"] == "argument" and ev["data"].get("reason", "") == "suspicion":
			accusations += 1
		elif ev["kind"] == "theft" and ev["data"]["asset"] == "cash":
			taken += int(ev["data"]["amount"])
			cash_thefts += 1
	out["accusations"] = accusations / per
	out["cash_per_theft"] = float(taken) / cash_thefts if cash_thefts > 0 else -1.0
	var thefts := 0
	var found := 0
	for inc in sim.incidents:
		if inc["family"] == "theft":
			thefts += 1
			if inc["discovered_at"] != null:
				found += 1
	out["theft_discovered_share"] = float(found) / thefts if thefts > 0 else -1.0
	var suspicions := 0
	var right := 0
	for bid in sim.beliefs:
		var b: Dictionary = sim.beliefs[bid]
		if b["source"] == "inferred" and b["claim"]["kind"] == "suspect":
			suspicions += 1
			var inc := incident_at(sim, b["claim"])
			if not inc.is_empty() and inc["responsible"] == b["claim"]["subject"]:
				right += 1
	out["suspicions_right_share"] = float(right) / suspicions if suspicions > 0 else -1.0
	return out


static func place_counts(sim) -> Dictionary:
	return sim.samples["at"]


static func stats(sim) -> Dictionary:
	## The numbers compared with Python (tools/sim_reference.py computes the same ones):
	##   per_resident_day: events of each kind per resident per day (for "chat": every chat)
	##   share: of resident-hours, where people were at the end of each hour; asleep: of resident-hours
	##   needs: mean hunger, energy, social, stress at the end of each hour
	##   money: mean wallet at the end; total cash in town (wallets and containers); open debts at the end
	var days: float = maxf(1.0, sim.t / float(DAY))
	var people := float(sim.ids.size())
	var counts: Dictionary = sim.events.counts()
	var per := {}
	for k in COMPARED_KINDS:
		per[k] = float(counts.get(k, 0)) / (people * days)
	# every chat, logged or not (a chat is logged only when gossip passes in it)
	per["chat"] = float(sim.stats.get("chats", 0)) / (people * days)
	var hours := maxf(1.0, float(sim.samples["hours"]))
	var share := {}
	for p in sim.samples["at"]:
		share[p] = sim.samples["at"][p] / hours
	var needs := {}
	for k in ["hunger", "energy", "social", "stress"]:
		needs[k] = sim.samples[k] / hours
	var wallets := 0
	for rid in sim.ids:
		wallets += sim.residents[rid].cash
	var town := wallets
	for cid in sim.world.containers:
		town += int(sim.world.containers[cid]["cash"])
	var open := 0
	for d in sim.world.debts:
		if d["settled"] < 0:
			open += 1
	var result := {"per_resident_day": per, "share": share, "asleep": sim.samples["asleep"] / hours, "needs": needs,
			"money": {"mean_wallet": wallets / people, "town_cash": float(town), "open_debts": float(open)}}
	if sim.memory_on:
		result["memory"] = memory_stats(sim)
	if sim.crime_on:
		result["crime"] = crime_stats(sim)
	return result


static func flatten(st: Dictionary) -> Dictionary:
	## {"per_resident_day.meal": 2.9, "share.home": 0.6, ...}
	var out := {}
	for k in st:
		if st[k] is Dictionary:
			for k2 in st[k]:
				out["%s.%s" % [k, k2]] = float(st[k][k2])
		else:
			out[k] = float(st[k])
	return out
