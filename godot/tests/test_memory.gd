## Perception, memory and gossip (scripts/sim/sim_memory.gd, sim_perception.gd, sim_gossip.gd), rule by rule,
## on a real town whose memories are cleared first so each scenario controls what people know. The
## whole-run provenance checks (every belief has a plausible source) are in scripts/sim/sim_check.gd and run
## from tests/test_sim.gd on every simulated month.
extends RefCounted

const Simulation = preload("res://scripts/sim/simulation.gd")
const SimCheck = preload("res://scripts/sim/sim_check.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Memory = preload("res://scripts/sim/sim_memory.gd")
const Perception = preload("res://scripts/sim/sim_perception.gd")
const Gossip = preload("res://scripts/sim/sim_gossip.gd")
const Decisions = preload("res://scripts/sim/sim_decisions.gd")
const Actions = preload("res://scripts/sim/sim_actions.gd")

const DAY := 1440


func run(t, _tree) -> void:
	_forgetting(t)
	_sight_and_hearing(t)
	_recognition(t)
	_gossip(t)
	_telling(t)
	_lending_caution(t)
	_help_from_hearsay(t)
	_suspicion(t)
	_whole_months(t)


func _fresh(seed := 3):
	## A town at Day 1 10:00 where nobody knows anything yet, everyone awake, everyone at home.
	var sim = Simulation.new({"seed": seed, "days": 3})
	sim.t = SimClock.at(1, 10)
	for rid in sim.ids:
		sim.memory[rid] = Memory.new(rid)
		sim.residents[rid].asleep = false
	sim.beliefs = {}
	sim.world.debts.clear()  # no old debts either, so nothing else competes with what a scenario sets up
	return sim


func _place(sim, rid: String, node: String) -> void:
	sim.intervals[rid] = [[node, 0, -1]]


static func _apart(sim, a: String) -> Array:
	## Residents of other households than ``a``.
	var out := []
	for x in sim.ids:
		if sim.residents[x].household != sim.residents[a].household:
			out.append(x)
	return out


func _forgetting(t) -> void:
	t.begin("memories fade by salience; important ones and those near an incident stay; recollection may slip")
	var b := {"claim": Memory.claim("presence", {"subject": "x", "location": "square", "start": 0, "end": 0}),
			"acquired": 0, "confidence": 0.9, "salience": Memory.SALIENCE["presence"]}
	t.check(Memory.recall(b, DAY, [])[0], "a presence is remembered after a day")
	t.check(Memory.recall(b, 4 * DAY, [])[1] < Memory.recall(b, DAY, [])[1], "and less surely after four")
	t.check(not Memory.recall(b, 5 * DAY, [])[0], "a passing presence (salience 0.12) is gone after 4.5 days")
	t.check(Memory.recall(b, 5 * DAY, [[0, 60]])[0], "unless it was near an incident the holder goes over")
	var d := b.duplicate()
	d["claim"] = Memory.claim("debt", {"subject": "x", "other": "y", "amount": 50})
	d["salience"] = Memory.SALIENCE["debt"]
	t.check(Memory.recall(d, 60 * DAY, [])[0], "a debt (salience 0.9) is never forgotten")
	var slips := 0
	var sim = _fresh()
	for i in 200:
		var r := Memory.recollect(b, DAY, sim.rng)
		if r["error"] == "misremembered_time":
			slips += 1
			t.check(absi(r["claim"]["start"] - b["claim"]["start"]) in [30, 45, 60], "a slip is 30 to 60 minutes")
	t.check(slips > 30 and slips < 90, "about 30% of old sightings come back at the wrong time (%d of 200)" % slips)
	t.eq(Memory.recollect(d, DAY, sim.rng)["error"], null, "a debt is not misremembered")
	t.end()


func _sight_and_hearing(t) -> void:
	t.begin("an argument is seen where it happens, heard next door, unknown further away")
	var sim = _fresh()
	var a: String = sim.ids[0]
	var b: String = sim.ids[1]
	var others: Array = sim.ids.slice(2)
	var at_pub: String = others[0]
	var asleep_pub: String = others[1]
	var square: String = others[2]
	var mill: String = others[3]
	for rid in [a, b, at_pub, asleep_pub]:
		_place(sim, rid, "pub")
	_place(sim, square, "square")
	_place(sim, mill, "mill")
	sim.residents[asleep_pub].asleep = true
	for rid in others.slice(4):
		_place(sim, rid, "road")  # two steps from the pub: out of earshot for a shout (audibility 2)
	var saw := 0
	var heard_sq := 0
	var heard_asleep := 0
	var trials := 60
	for i in trials:
		var tt: int = SimClock.at(1, 10) + i * 61
		var ev: Dictionary = sim.emit("argument", "pub", [a], {"targets": [b], "audibility": 2, "time": tt})
		var seen := Memory.claim("argument", {"subject": a, "other": b, "location": "pub", "start": tt})
		var noise := Memory.claim("noise", {"location": "pub", "start": tt, "detail": "raised voices"})
		Perception.broadcast(sim, ev, seen, noise, a)
		saw += 1 if sim.perceived.get(at_pub + "|" + ev["id"]) == "saw" else 0
		heard_sq += 1 if sim.perceived.get(square + "|" + ev["id"]) == "heard" else 0
		heard_asleep += 1 if sim.perceived.get(asleep_pub + "|" + ev["id"]) == "heard" else 0
	t.eq(saw, trials, "someone awake in the room sees every argument")
	t.check(heard_sq > trials * 0.6, "the square (next door) hears most of them: %d of %d" % [heard_sq, trials])
	t.check(heard_asleep > trials * 0.25 and heard_asleep < trials * 0.75, "a sleeper in the room wakes to about half: %d" % heard_asleep)
	t.eq(sim.memory[mill].beliefs.size(), 0, "nobody at the mill (three steps away) knows of any of it")
	for rid in others.slice(4):
		t.eq(sim.memory[rid].beliefs.size(), 0, "%s, two steps away, knows nothing" % rid)
	for bid in sim.beliefs:
		var bl: Dictionary = sim.beliefs[bid]
		t.check(bl["holder"] != a and bl["holder"] != b, "a party is not a witness of their own argument")
		if bl["holder"] == square:
			t.eq(bl["source"], "heard", "the square only hears it")
			t.eq(bl["claim"]["kind"], "noise", "and hears a noise, not who argued about what")
	t.end()


func _recognition(t) -> void:
	t.begin("recognition fails in the dark and with strangers; a wrong guess falls on someone disliked")
	var sim = _fresh()
	var obs: String = sim.ids[0]
	var subj: String = _apart(sim, obs)[0]
	var day := 0
	var night := 0
	var wrong := 0
	var trials := 400
	sim.residents[obs].r(subj)["trust"] = 0.2
	sim.residents[obs].r(subj)["affection"] = 0.2
	var disliked: String = _apart(sim, obs)[1]
	for x in sim.ids:
		if x != obs:
			sim.residents[obs].r(x)["resentment"] = 0.0
	sim.residents[obs].r(disliked)["resentment"] = 1.0
	var picked_disliked := 0
	for i in trials:
		var who_day: Array = Perception.identify(sim, obs, subj, "grocery", SimClock.at(1, 12))
		day += 1 if who_day[0] == subj else 0
		var who: Array = Perception.identify(sim, obs, subj, "square", SimClock.at(1, 23))
		night += 1 if who[0] == subj else 0
		if who[1] == "misidentified":
			wrong += 1
			t.check(who[0] != subj, "a misidentification names someone else")
			picked_disliked += 1 if who[0] == disliked else 0
	t.check(day > trials * 0.93, "indoors by day, people are recognised (%d of %d)" % [day, trials])
	t.check(night < trials * 0.5, "a stranger on the dark square mostly isn't (%d of %d)" % [night, trials])
	t.check(wrong > 0, "sometimes someone else is named")
	t.check(picked_disliked * 3 > wrong, "the wrong name is mostly someone disliked (%d of %d; 1 in 8 by chance)" % [
			picked_disliked, wrong])
	t.end()


func _gossip(t) -> void:
	t.begin("gossip: news passes in chats, never the listener's own troubles, never about someone the speaker loves")
	var sim = _fresh()
	var s: String = sim.ids[0]
	var l: String = _apart(sim, s)[0]
	var x: String = _apart(sim, s)[1]
	var speaker = sim.residents[s]
	var listener = sim.residents[l]
	var now: int = sim.t
	var hardship := Memory.claim("hardship", {"subject": x, "start": now - 60, "detail": "asking around for money"})
	var b: Dictionary = sim.add_belief(s, hardship, "self", 0.9, now - 60, {"event": null})
	speaker.r(x)["affection"] = 0.9
	t.eq(Gossip.pick_gossip(sim, speaker, listener, now), [], "someone fond of x keeps x's hardship to themselves")
	speaker.r(x)["affection"] = 0.3
	var picked: Array = Gossip.pick_gossip(sim, speaker, listener, now)
	t.check(picked.size() == 1 and picked[0]["id"] == b["id"], "otherwise it comes up in conversation")
	var own: Dictionary = sim.add_belief(s, Memory.claim("hardship", {"subject": l, "start": now - 30}), "self", 0.9,
			now - 30, {"event": null})
	for g in Gossip.pick_gossip(sim, speaker, listener, now):
		t.check(g["id"] != own["id"], "nobody is told of their own hardship")
	var old: Dictionary = sim.add_belief(s, Memory.claim("argument", {"subject": x, "other": l, "start": now - 5 * DAY}),
			"saw", 0.9, now - 5 * DAY, {"event": null})
	sim.memory[s].beliefs.erase(old)
	sim.memory[s].beliefs.push_front(old)
	for g in Gossip.pick_gossip(sim, speaker, listener, now):
		t.check(g["id"] != old["id"], "news more than four days old is not passed on")
	Gossip.tell(sim, s, l, b, "E-chat", now)
	t.check(l in b["told_to"], "the speaker remembers having told them")
	t.eq(Gossip.pick_gossip(sim, speaker, listener, now + 10), [], "and doesn't tell them again")
	t.end()


func _telling(t) -> void:
	t.begin("what is told stays told: trust lowers confidence, hearsay never outranks seeing")
	var sim = _fresh()
	var s: String = sim.ids[0]
	var l: String = _apart(sim, s)[0]
	var x: String = _apart(sim, s)[1]
	var now: int = sim.t
	var c := Memory.claim("argument", {"subject": x, "other": s, "location": "pub", "start": now - 30})
	var b: Dictionary = sim.add_belief(s, c, "saw", 0.9, now - 30, {"event": null})
	sim.residents[l].r(s)["trust"] = 0.5
	Gossip.tell(sim, s, l, b, "E-chat", now)
	var told = sim.memory[l].find(c)
	if told == null:  # the start time may have drifted in the telling
		told = sim.memory[l].beliefs[-1]
	t.eq(told["source"], "told", "the listener was told")
	t.eq(told["told_by"], s, "by the speaker")
	t.eq(told["via"], b["id"], "copied from the speaker's own belief")
	t.check(absf(told["confidence"] - 0.9 * (0.55 + 0.35 * 0.5)) < 0.002, "trusted as far as the speaker is")
	var seen: Dictionary = sim.add_belief(l, c.duplicate(), "saw", 0.9, now, {"event": null})
	var again: Dictionary = sim.add_belief(l, c.duplicate(), "told", 0.5, now + 5, {"event": null, "told_by": s})
	t.eq(again["id"], seen["id"], "being told what you saw yourself leaves it as seen")
	# hedged sightings lose their "I think" in the telling now and then; times drift; both are marked
	var inflated := 0
	var drifted := 0
	var listener: String = _apart(sim, s)[2]
	for i in 300:
		var hedged := Memory.claim("sighting", {"subject": x, "location": "square", "start": now - 120,
				"end": now - 120, "detail": "passing, time %d" % i, "hedged": true})
		var hs: Dictionary = sim.add_belief(s, hedged, "saw", 0.6, now - 120, {"event": null})
		var before: int = sim.beliefs.size()
		Gossip.tell(sim, s, listener, hs, "E-chat", now + i)
		t.eq(sim.beliefs.size(), before + 1, "each telling of a new sighting is a new belief")
		var nb: Dictionary = sim.beliefs["B%06d" % sim.beliefs.size()]
		if nb["error"] == "certainty_inflated":
			inflated += 1
			t.check(not nb["claim"]["hedged"], "an inflated sighting has lost its hedge")
		elif nb["error"] == "time_distorted":
			drifted += 1
			t.check(nb["claim"]["start"] != hedged["start"], "a distorted time differs")
		else:
			t.eq(nb["claim"]["start"], hedged["start"], "otherwise the time is passed on as it was")
	t.check(inflated > 0 and drifted > 0, "both distortions happen (%d inflated, %d drifted)" % [inflated, drifted])
	t.end()


func _lending_caution(t) -> void:
	t.begin("lenders hold back for each unpaid debt they know of, and only those they know of")
	var sim = _fresh()
	var r: String = sim.ids[0]
	var x: String = _apart(sim, r)[0]
	var y: String = _apart(sim, r)[1]
	var base: float = Actions.loan_chance(sim, sim.residents[r], x)
	sim.add_belief(y, Memory.claim("debt", {"subject": r, "other": x, "amount": 40, "detail": "loan"}), "self", 1.0,
			0, {"event": null})
	t.eq(Actions.loan_chance(sim, sim.residents[r], x), base, "a debt the lender never heard of changes nothing")
	sim.add_belief(x, Memory.claim("debt", {"subject": r, "other": y, "amount": 40, "detail": "loan"}), "told", 0.6, 0,
			{"event": null, "told_by": y})
	t.check(absf(Actions.loan_chance(sim, sim.residents[r], x) - (base - 0.25)) < 1e-9, "one known unpaid debt: -0.25")
	sim.add_belief(x, Memory.claim("debt", {"subject": r, "other": y, "amount": 40, "start": 30, "detail": "repaid"}),
			"told", 0.6, 30, {"event": null, "told_by": y})
	t.check(absf(Actions.loan_chance(sim, sim.residents[r], x) - base) < 1e-9, "once they hear it was repaid, it's forgiven")
	sim.memory_on = false
	t.eq(Actions.loan_chance(sim, sim.residents[r], x), base, "(and without memory, nothing is known)")
	t.end()


func _help_from_hearsay(t) -> void:
	t.begin("someone who hears that a friend is struggling may help, but only if they have heard")
	var sim = _fresh()
	var h: String = sim.ids[0]
	var x: String = _apart(sim, h)[0]
	var r = sim.residents[h]
	r.cash = 150
	r.traits["empathy"] = 1.0
	for o in sim.ids:
		if o != h:
			r.r(o)["resentment"] = 0.0
	r.r(x)["affection"] = 0.9
	var before: Dictionary = Decisions._social_intent(sim, r, sim.t, 0.0)
	t.check(before.is_empty() or before["kind"] != "help", "nobody helps a struggle they know nothing of")
	sim.add_belief(h, Memory.claim("hardship", {"subject": x, "start": sim.t - 60, "detail": "cannot pay for food"}),
			"told", 0.5, sim.t - 30, {"event": null, "told_by": _apart(sim, h)[1]})
	var after: Dictionary = Decisions._social_intent(sim, r, sim.t, 0.0)
	t.eq(after.get("kind"), "help", "hearing of it is enough")
	t.eq(after.get("target"), x, "and the help goes to the one who is struggling")
	t.end()


func _suspicion(t) -> void:
	t.begin("suspicion: from a loss and what the holder saw nearby, to an accusation the accused then knows of")
	var sim = _fresh()
	var owner: String = sim.world.containers["till:grocery"]["owners"][0]
	var z: String = _apart(sim, owner)[0]
	var a = sim.residents[owner]
	a.traits["caution"] = 0.0
	a.traits["empathy"] = 0.0
	for o in sim.ids:
		if o != owner:
			a.r(o)["resentment"] = 0.0
	var now: int = sim.t
	var loss := Memory.claim("loss", {"other": owner, "location": "grocery", "start": now - 240, "end": now - 60,
			"amount": 30, "obj": "till:grocery", "detail": "cash missing from the grocery till"})
	sim.add_belief(owner, loss, "self", 0.95, now - 50, {"event": null})
	sim.add_belief(owner, Memory.claim("presence", {"subject": z, "location": "grocery", "start": now - 200,
			"end": now - 150}), "saw", 0.9, now - 200, {"event": null})
	sim.add_belief(owner, Memory.claim("hardship", {"subject": z, "start": now - 300}), "told", 0.6, now - 300,
			{"event": null, "told_by": _apart(sim, owner)[1]})
	Gossip.infer_suspicions(sim, owner, now)
	var sus: Array = sim.memory[owner].of_kind(["suspect"])
	t.eq(sus.size(), 1, "one suspicion")
	if sus.is_empty():
		t.end()
		return
	var s: Dictionary = sus[0]
	t.eq(s["claim"]["subject"], z, "of the one seen near the till who needs money")
	t.eq(s["source"], "inferred", "inferred, not seen")
	t.check(s["premises"].size() >= 3, "from the loss, the sighting and the hardship")
	t.check(Gossip.has_stake(sim, owner, s), "the till's owner has a stake")
	var plan: Dictionary = Decisions._social_intent(sim, a, now, 0.0)
	t.eq([plan.get("kind"), plan.get("reason"), plan.get("target")], ["confront", "suspicion", z], "and goes to confront")
	_place(sim, owner, "grocery")
	_place(sim, z, "grocery")
	sim.residents[z].asleep = false
	Actions.confront(sim, a, z, plan, now + 46)
	var accused: Array = sim.memory[z].of_kind(["suspect"])
	t.eq(accused.size(), 1, "the accused now knows they are suspected")
	if not accused.is_empty():
		t.eq([accused[0]["source"], accused[0]["told_by"], accused[0]["via"]], ["told", owner, s["id"]],
				"because the accuser told them, from the accuser's suspicion")
	t.end()


func _whole_months(t) -> void:
	t.begin("whole months: rumours travel through people, mistakes happen, nobody knows what they couldn't")
	var deep := 0
	var kinds := {}
	for profile in ["normal", "tension"]:
		var sim = Simulation.new({"seed": 4, "days": 30, "profile": profile}).run()
		var found: Array = SimCheck.problems(sim)
		t.check(found.is_empty(), "%s: %d problems, first: %s" % [profile, found.size(), found.slice(0, 3)])
		for bid in sim.beliefs:
			var b: Dictionary = sim.beliefs[bid]
			if b["error"]:
				kinds[b["error"]] = true
			if b["source"] == "told" and b["via"] and sim.beliefs[b["via"]]["source"] == "told":
				deep += 1
		var argument := {}
		for ev in sim.events.events:
			if ev["kind"] == "argument":
				argument = ev
				break
		if not argument.is_empty():
			# everyone who knows of this argument took part, saw or heard it, or was told by someone who knew
			for bid in sim.beliefs:
				var b: Dictionary = sim.beliefs[bid]
				var root: Dictionary = SimCheck._root(sim, b)
				if root["event"] != argument["id"]:
					continue
				var first: String = root["holder"]
				t.check(SimCheck.involved(first, argument) or sim.perceived.has(first + "|" + argument["id"]),
						"%s knew of %s first-hand without being there" % [first, argument["id"]])
	t.check(deep > 0, "some news is passed on by people who were themselves told (%d)" % deep)
	t.check(kinds.has("misidentified") and kinds.has("time_distorted"), "misidentifications and drifting times happen: %s" % kinds.keys())
	t.end()
