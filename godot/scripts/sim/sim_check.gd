## Integrity checks and summary statistics for a simulation run, used by tests/test_sim.gd and the demo
## (tests/run_sim.gd). The statistics use exactly the definitions in tools/sim_reference.py, which measures
## the Python simulation the same way.
extends RefCounted

const SimClock = preload("res://scripts/sim/sim_clock.gd")

const DAY := 1440
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
		var c: Dictionary = sim.world.containers[cid]
		if c["cash"] != c["expected_cash"] or c["food"] != c["expected_food"]:
			out.append("%s holds %d cash and %d food; its owners expect %d and %d" % [c["label"], c["cash"], c["food"],
					c["expected_cash"], c["expected_food"]])


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
	return {"per_resident_day": per, "share": share, "asleep": sim.samples["asleep"] / hours, "needs": needs,
			"money": {"mean_wallet": wallets / people, "town_cash": float(town), "open_debts": float(open)}}


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
