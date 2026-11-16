## Turning beliefs into first-person testimony (mirrors mystery/cases/testimony.py).
##
## Every sentence is rendered from a claim the speaker actually holds (as they recall it now), phrased by where
## it came from: "I saw", "I heard", "<name> told me", "I reckon". A lie is rendered by the same functions from
## a made-up account, so it reads exactly like the truth. Nothing here looks at what really happened.
extends RefCounted

const SimClock = preload("res://scripts/sim/sim_clock.gd")

const DAY := 1440
const THEY_FIXES := [[" they was ", " they were "], [" they has ", " they have "], [" they is ", " they are "],
		[" they owes ", " they owe "]]


# ---------------------------------------------------------------- times and names
static func r15(t: int) -> int:
	return roundi(t / 15.0) * 15


static func fmt_approx(t: int) -> String:
	var r := r15(t)
	return "around %s on Day %d" % [SimClock.fmt_clock(r), SimClock.day_of(r)]


static func fmt_span(start: int, end: int) -> String:
	var a := r15(start)
	var b := r15(end)
	if b <= a:
		return fmt_approx(start)
	if SimClock.day_of(a) == SimClock.day_of(b):
		return "from about %s to %s on Day %d" % [SimClock.fmt_clock(a), SimClock.fmt_clock(b), SimClock.day_of(a)]
	return "from about %s on Day %d to %s on Day %d" % [SimClock.fmt_clock(a), SimClock.day_of(a),
			SimClock.fmt_clock(b), SimClock.day_of(b)]


static func n(sim, rid) -> String:
	if rid == null or String(rid) == "":
		return "someone"
	return sim.residents[rid].first if sim.residents.has(rid) else String(rid)


static func when(c: Dictionary) -> String:
	if c["start"] == null:
		return ""
	if c["end"] != null and int(c["end"]) - int(c["start"]) >= 30:
		return fmt_span(c["start"], c["end"])
	return fmt_approx(c["start"])


static func place(sim, loc) -> String:
	return sim.world.name_of(loc) if loc != null and String(loc) != "" else "somewhere"


static func veh(sim, vid) -> String:
	if vid != null and sim.world.vehicles.has(vid):
		return sim.world.vehicles[vid]["name"]
	return "a vehicle"


static func amount(c: Dictionary) -> String:
	return str(c["amount"]) if c["amount"] != null else "None"


static func capitalized(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s


# ---------------------------------------------------------------- phrases
static func phrases(sim, c: Dictionary, teller = null) -> Array:
	## [perceptual phrase for "I saw/heard ...", proposition for "X told me ..."]. When the teller is a party to
	## their own story they become "they"/"them".
	var pp := _phrases(sim, c, teller)
	var prop: String = pp[1]
	if teller != null and c["subject"] == teller and prop.begins_with("they "):
		prop = " " + prop
		for fix in THEY_FIXES:
			prop = prop.replace(fix[0], fix[1])
		prop = prop.strip_edges()
	return [pp[0], prop]


static func _phrases(sim, c: Dictionary, teller) -> Array:
	var k: String = c["kind"]
	var who := n(sim, c["subject"])
	var other := n(sim, c["other"])
	if teller != null and c["other"] == teller:
		other = "them"
	if teller != null and c["subject"] == teller and not (k in ["presence", "sighting"]):
		who = "they"
	var at := place(sim, c["location"])
	var wh := when(c)
	var detail: String = c["detail"]
	match k:
		"presence":
			return ["%s at %s %s" % [who, at, wh], "%s was at %s %s" % [who, at, wh]]
		"sighting":
			var tail := (", " + detail) if detail != "" else ""
			if c["subject"] == null:
				return ["someone at %s %s%s — too dark to tell who" % [at, wh, tail],
						"someone was at %s %s%s" % [at, wh, tail]]
			if c["hedged"]:
				return ["someone at %s %s%s; I think it was %s, but it was dark" % [at, wh, tail, who],
						"%s was at %s %s%s, though it was dark" % [who, at, wh, tail]]
			return ["%s at %s %s%s" % [who, at, wh, tail], "%s was at %s %s%s" % [who, at, wh, tail]]
		"noise":
			var door := "door" in detail
			var voice := ""
			if c["subject"] != null:
				voice = ("; I think it was %s" % who) if door else ("; I think one of the voices was %s" % who)
			var where_ := "at" if door else "from"
			var tail2 := "" if door else ". I didn't see anything"
			return ["%s %s %s %s%s%s" % [detail, where_, at, wh, voice, tail2],
					"there was %s at %s %s" % [detail, at, wh]]
		"argument":
			return ["%s confront %s at %s %s — %s" % [who, other, at, wh, detail],
					"%s confronted %s at %s %s — %s" % [who, other, at, wh, detail]]
		"assault":
			return ["%s attack %s at %s %s" % [who, other, at, wh], "%s attacked %s at %s %s" % [who, other, at, wh]]
		"saw_collision":
			var hit := "someone" if c["other"] != null else "the fence"
			var driver := ("; I think %s was driving" % who) if c["subject"] != null else ""
			return ["%s hit %s on Mill Road %s%s" % [veh(sim, c["obj"]), hit, wh, driver],
					"%s hit %s on Mill Road %s" % [veh(sim, c["obj"]), hit, wh]]
		"loss":
			var second := detail
			if c["start"] != null:
				var e: int = c["end"] if c["end"] != null and int(c["end"]) != 0 else c["start"]
				second = "%s; it went missing %s" % [detail, fmt_span(c["start"], e)]
			return ["%s (%s)" % [detail, when(c)], second]
		"damage":
			return ["%s %s" % [detail, wh], "about %s, %s" % [detail, wh]]
		"missing":
			return ["no sign of %s all day" % who, "nobody had seen %s all day" % who]
		"injury":
			if detail.begins_with("lying"):
				return ["%s %s %s" % [who, detail, wh], "%s was found %s %s" % [who, detail, wh]]
			return ["%s hurt — %s — %s" % [who, detail, wh], "%s was hurt — %s — %s" % [who, detail, wh]]
		"death":
			return ["%s dead at %s %s" % [who, at, wh], "%s was found dead at %s %s" % [who, at, wh]]
		"intoxicated":
			return ["%s the worse for drink at %s %s" % [who, at, wh], "%s was drunk at %s %s" % [who, at, wh]]
		"vehicle_damage":
			var owner := (" (%s's)" % who) if c["subject"] != null else ""
			return ["%s%s with %s %s" % [veh(sim, c["obj"]), owner, detail, wh],
					"%s%s had %s %s" % [veh(sim, c["obj"]), owner, detail, wh]]
		"repair":
			return ["%s bring %s in for repairs %s, saying: \"%s\"" % [who, veh(sim, c["obj"]), wh, detail],
					"%s had %s repaired %s and said: \"%s\"" % [who, veh(sim, c["obj"]), wh, detail]]
		"debt":
			var p := ""
			if detail == "repaid":
				p = "%s paid %s back %s crowns %s" % [who, other, amount(c), wh]
			elif detail == "overdue":
				p = "%s is behind on paying %s back (%s crowns)" % [who, other, amount(c)]
			elif detail == "credit":
				p = "%s has been taking food on credit from %s (%s crowns owed)" % [who, other, amount(c)]
			else:
				p = "%s owes %s %s crowns" % [who, other, amount(c)]
			return [p, p]
		"loan":
			return ["%s borrowing money from %s %s" % [who, other, wh], "%s borrowed money from %s %s" % [who, other, wh]]
		"refusal":
			return ["%s turn %s down for %s %s" % [who, other, detail, wh], "%s refused %s %s %s" % [who, other, detail, wh]]
		"hardship":
			return ["%s struggling for money" % who, "%s has been short of money — %s" % [who, detail]]
		"rent_missed":
			return ["%s miss the rent" % who, "%s couldn't pay the rent to %s" % [who, other]]
		"grudge":
			var a := "them" if who == "they" else who
			var b := "them" if other == "they" else other
			return ["", "there's bad blood between %s and %s — %s" % [a, b, detail]]
		"laid_off":
			return ["", "%s laid %s off from the mill" % [other, who]]
		"help":
			return ["%s help %s out with money" % [who, other], "%s gave %s some money to tide them over" % [who, other]]
		"reconcile":
			return ["%s try to make peace with %s" % [who, other], "%s tried to make peace with %s (%s)" % [who, other, detail]]
		"confession":
			return ["%s confess to %s" % [who, other], "%s confessed something to %s" % [who, other]]
		"suspect":
			return ["", "%s had something to do with %s" % [who, detail]]
		"struck":
			var d := ("%s hit %s" % [who, other]) if c["subject"] != null else ("a vehicle hit %s" % other)
			return [d + " on Mill Road " + wh, d + " on Mill Road " + wh]
		"fall":
			return ["%s fall into the ditch" % who, "%s fell into the ditch on Mill Road %s" % [who, wh]]
		"purchase":
			return ["%s buying food" % who, "%s bought %s at the grocery %s" % [who, detail, wh]]
		"collision_self":
			return ["", "%s %s on Mill Road %s driving %s" % [who, detail, wh, veh(sim, c["obj"])]]
	return [k, k]


static func first_person(sim, speaker: String, c: Dictionary) -> String:
	## Sentences about the speaker's own experience ("" where there is no such sentence).
	var k: String = c["kind"]
	var wh := when(c)
	var at := place(sim, c["location"])
	var other := n(sim, c["other"])
	var detail: String = c["detail"]
	if k == "debt" and c["subject"] == speaker:
		match detail:
			"repaid":
				return "I paid %s back the %s crowns I owed, %s." % [other, amount(c), wh]
			"overdue":
				return "I'm behind on paying %s back — %s crowns." % [other, amount(c)]
			"credit":
				return "I've been taking food on credit from %s; I owe %s crowns." % [other, amount(c)]
		return "I owe %s %s crowns." % [other, amount(c)]
	if k == "debt" and c["other"] == speaker:
		var who := n(sim, c["subject"])
		match detail:
			"repaid":
				return "%s paid me back %s crowns %s." % [who, amount(c), wh]
			"overdue":
				return "%s owes me %s crowns and is late paying." % [who, amount(c)]
			"credit":
				return "%s has been taking food on credit; owes me %s crowns." % [who, amount(c)]
		return "%s owes me %s crowns." % [who, amount(c)]
	if k == "refusal" and c["subject"] == speaker:
		return "I turned %s down when they asked me for %s, %s." % [other, detail, wh]
	if k == "refusal" and c["other"] == speaker:
		return "I asked %s for %s %s. They said no." % [n(sim, c["subject"]), detail, wh]
	if k == "hardship":
		return "%s came asking me for money, %s. Times are hard for them." % [n(sim, c["subject"]), wh]
	if k == "argument":
		if c["subject"] == speaker:
			return "I had it out with %s at %s %s — %s." % [other, at, wh, detail]
		return "%s came at me at %s %s — %s." % [n(sim, c["subject"]), at, wh, detail]
	if k == "assault" and c["other"] == speaker:
		return "%s attacked me at %s %s." % [n(sim, c["subject"]), at, wh]
	if k == "assault" and c["subject"] == speaker:
		return "%s and I came to blows at %s %s. They started it." % [n(sim, c["other"]), at, wh]
	if k == "loss":
		var span := ""
		if c["start"] != null and c["end"] != null:
			span = fmt_span(c["start"], c["end"])
		return "I found %s. It went missing %s." % [detail, span]
	if k == "struck" and c["other"] == speaker:
		if c["subject"] != null:
			return "%s hit me with %s on Mill Road %s. They stopped to help." % [n(sim, c["subject"]), veh(sim, c["obj"]), wh]
		return "Something hit me on Mill Road %s — %s, I think. It didn't stop. I never saw the driver." % [wh, detail]
	if k == "fall":
		return "I slipped into the ditch on Mill Road %s. I'd had a few." % wh
	if k == "injury" and c["subject"] == speaker:
		return "I got hurt on %s %s, and I honestly can't remember how." % [at, wh]
	if k == "injury" and detail.begins_with("lying"):
		return "I found %s %s, %s." % [n(sim, c["subject"]), detail, wh]
	if k == "injury":
		return "%s was hurt — %s — %s." % [n(sim, c["subject"]), detail, wh]
	if k == "death":
		return "I found %s dead at %s %s." % [n(sim, c["subject"]), at, wh]
	if k == "purchase":
		return "I bought %s at the grocery %s and paid %s crowns." % [detail, wh, amount(c)]
	if k == "grudge":
		var them = c["other"] if c["subject"] == speaker else c["subject"]
		return "%s and I have never got on — %s." % [n(sim, them), detail]
	if k == "laid_off":
		if c["subject"] == speaker:
			return "%s laid me off from the mill." % other
		return "I had to let %s go from the mill." % n(sim, c["subject"])
	if k == "loan":
		return ""
	if k == "help":
		if c["subject"] == speaker:
			return "I gave %s a little money to tide them over." % other
		return "%s gave me some money to tide me over." % n(sim, c["subject"])
	if k == "reconcile":
		var them2 = c["other"] if c["subject"] == speaker else c["subject"]
		if c["subject"] == speaker:
			return "I tried to make peace with %s (%s)." % [n(sim, them2), detail]
		return "%s came to make peace with me (%s)." % [n(sim, them2), detail]
	if k == "rent_missed":
		if c["subject"] == speaker:
			return "I couldn't make the rent to %s." % other
		return "%s couldn't pay me the rent." % n(sim, c["subject"])
	if k == "collision_self":
		return "I %s on Mill Road %s, driving %s. I stopped and owned up." % [detail, wh, veh(sim, c["obj"])]
	if k == "confession":
		if c["subject"] == speaker:
			return "I confessed to %s." % other
		return "%s confessed to me." % n(sim, c["subject"])
	return ""


static func render(sim, speaker: String, b: Dictionary, claim: Dictionary) -> String:
	## What the speaker says about this belief, as they recall it now.
	var source: String = b["source"]
	if source == "self":
		var text := first_person(sim, speaker, claim)
		if text != "":
			return text
	var pp := phrases(sim, claim)
	var percept: String = pp[0]
	var prop: String = pp[1]
	if source == "saw" and claim["kind"] == "debt":
		return "I know %s." % percept  # a state of affairs, not a sight
	if source == "saw" and percept != "":
		return "I saw %s." % percept
	if source == "heard" and percept != "":
		return "I heard %s." % percept
	if source == "told":
		var teller := n(sim, b["told_by"])
		var told: String = phrases(sim, claim, b["told_by"])[1]
		var about := "about " if claim["kind"] == "loss" else ""
		return "%s told me %s%s." % [teller, about, told]
	if source == "inferred":
		if claim["kind"] == "suspect":
			return "If you ask me, %s." % prop
		if claim["kind"] == "assault":
			return "I think %s pushed me. It's all hazy." % n(sim, claim["subject"])
		return "I reckon %s." % prop
	return capitalized(prop) + "."


# ---------------------------------------------------------------- whereabouts
static func segments(sim, rid: String, a: int, b: int) -> Array:
	## [[place, from, to]] of where ``rid`` was between ``a`` and ``b``, consecutive stays at one place merged.
	var out := []
	for iv in sim.intervals[rid]:
		var s: int = iv[1]
		var e2: int = b if int(iv[2]) < 0 else int(iv[2])
		if e2 <= a or s >= b:
			continue
		var s2 := maxi(s, a)
		e2 = mini(e2, b)
		if not out.is_empty() and out[-1][0] == iv[0]:
			out[-1][2] = e2
		else:
			out.append([iv[0], s2, e2])
	return out


static func describe_segments(sim, rid: String, segs: Array, hazy_after = null) -> String:
	## Every move with its times: the exact account, told when asked to be precise.
	var parts := PackedStringArray()
	var home: String = sim.residents[rid].home
	for i in segs.size():
		var loc: String = segs[i][0]
		var s: int = segs[i][1]
		var e: int = segs[i][2]
		var outdoor: bool = sim.world.locations[loc]["outdoor"]
		if outdoor and e - s < 25 and 0 < i and i < segs.size() - 1:
			parts.append("around %s I passed through %s" % [SimClock.fmt_clock(s), sim.world.name_of(loc)])
			continue
		var label := "at home" if loc == home else "at " + sim.world.name_of(loc)
		var night := ""
		if loc == home and e - s >= 4 * 60:
			night = ", asleep for most of it"
		parts.append("from about %s to %s I was %s%s" % [SimClock.fmt_clock(r15(s)), SimClock.fmt_clock(r15(e)), label,
				night])
		if hazy_after != null and e > int(hazy_after) and loc != home:
			parts.append("after that it gets hazy — I'd had a fair bit to drink")
			hazy_after = null
	if parts.is_empty():
		return "I don't rightly remember."
	return "On Day %d: %s." % [SimClock.day_of(segs[0][1]), "; ".join(parts)]


static func concise_segments(sim, segs: Array, keep: Array) -> Array:
	## What someone mentions when asked where they were: the places they spent time, not every street they
	## crossed (short trips outdoors are left out unless the place is in ``keep``, the place the case is about).
	var out := []
	for i in segs.size():
		var loc: String = segs[i][0]
		var s: int = segs[i][1]
		var e: int = segs[i][2]
		var passing: bool = sim.world.locations[loc]["outdoor"] and e - s < 25 and 0 < i and i < segs.size() - 1
		if passing and not (loc in keep):
			continue
		if not out.is_empty() and out[-1][0] == loc:
			out[-1][2] = e
		else:
			out.append([loc, s, e])
	return out


static func describe_concise(sim, rid: String, segs: Array, hazy_after = null) -> String:
	## "On Day 23, from about 14:15 I was at the grocery; at the pub from about 17:00; home around 19:15 ..."
	if segs.is_empty():
		return "I don't rightly remember."
	var home: String = sim.residents[rid].home
	var parts := PackedStringArray()
	var been := {}
	var day := SimClock.day_of(r15(segs[0][1]))
	for i in segs.size():
		var loc: String = segs[i][0]
		var s: int = segs[i][1]
		var e: int = segs[i][2]
		var t := SimClock.fmt_clock(r15(s))
		var d := SimClock.day_of(r15(s))
		var lead := ("on Day %d " % d) if d != day and i > 0 else ""
		day = d
		var at: String = sim.world.name_of(loc)
		if sim.world.locations[loc]["outdoor"] and e - s < 25 and 0 < i and i < segs.size() - 1:
			parts.append("%salong %s around %s" % [lead, at, t])
		elif i == 0:
			parts.append("from about %s I was %s" % [t, "at home" if loc == home else "at " + at])
		elif loc == home:
			parts.append("%shome around %s%s" % [lead, t, " and to bed" if e - s >= 4 * 60 else ""])
		else:
			parts.append("%s%sat %s from about %s" % [lead, "back " if been.has(loc) else "", at, t])
		been[loc] = true
		if hazy_after != null and e > int(hazy_after) and loc != home:
			parts.append("after that it gets hazy — I'd had a fair bit to drink")
			hazy_after = null
	return "On Day %d, %s." % [SimClock.day_of(r15(segs[0][1])), "; ".join(parts)]


# ---------------------------------------------------------------- summaries
static func join_names(names: Array) -> String:
	if names.size() == 1:
		return names[0]
	var head := PackedStringArray()
	for i in names.size() - 1:
		head.append(names[i])
	return ", ".join(head) + " and " + String(names[-1])


static func _behind(names: Array, late: Array, sep: String) -> String:
	if late.is_empty():
		return ""
	if late == names:
		return ", and they're behind with it" if names.size() > 1 else ", and is behind with it"
	return "%s%s %s behind with it" % [sep, join_names(late), "are" if late.size() > 1 else "is"]


static func summary_text(kind: String, source: String, names: Array, party := "", at := "", span := "",
		also := [], era := "recent") -> String:
	## One natural sentence standing for several statements of the same everyday kind. ``source`` is "told",
	## "saw", "self" or "mixed"; ``also`` is a second list of names (who was drunk, late paying, turned down).
	var who := join_names(names)
	var plural := names.size() > 1
	if kind == "seen":
		var drunk := ""
		if not also.is_empty():
			drunk = "; %s %s the worse for drink" % [join_names(also), "were" if also.size() > 1 else "was"]
		if not plural:
			return "I saw %s at %s more than once, %s%s." % [who, at, span, drunk]
		return "At %s, %s, I saw %s, coming and going%s." % [at, span, who, drunk]
	if kind == "owing":
		var lead: String = {"told": "From what I hear, ", "saw": "I know ", "mixed": "From what I know and hear, "}[source]
		return "%s%s %s %s money%s." % [lead, who, "owe" if plural else "owes", party, _behind(names, also, " — ")]
	var recent := era == "recent"
	if kind == "repaid":
		if source == "saw":
			if recent:
				return "I've seen %s paying %s back lately." % [who, party]
			return "I saw %s pay %s back a while ago." % [who, party]
		var verb := ("have been paying" if plural else "has been paying") if recent else "paid"
		return "I hear %s %s %s back %s." % [who, verb, party, "lately" if recent else "a while ago"]
	if kind == "refused":
		if source == "saw":
			if recent:
				return "I've seen %s ask %s for money lately and get turned down." % [party, who]
			return "I saw %s ask %s for money a while ago and get turned down." % [party, who]
		var asking := "has been asking around for money lately" if recent else "was asking around for money a while ago"
		return "I hear %s %s, and %s said no." % [party, asking, who]
	if kind == "i_asked":
		return "I asked %s for money %s, and %s said no." % [who, "lately" if recent else "a while ago",
				"they all" if plural else "they"]
	if kind == "owed_me":
		return "%s %s me money%s." % [who, "owe" if plural else "owes", _behind(names, also, "; ")]
	if kind == "repaid_me":
		if recent:
			return "%s %s paid me back lately." % [who, "have" if plural else "has"]
		return "%s paid me back a while ago." % who
	if kind == "asked_me":
		var came := ("%s %s come to me for money lately" % [who, "have" if plural else "has"]) if recent \
				else ("%s came to me for money a while ago" % who)
		if also.is_empty():
			return came + "."
		if also == names:
			return came + ", and I had to say no."
		return came + "; I had to turn %s down." % join_names(also)
	if kind == "suspected":
		var matter := party if party.begins_with("the ") else "the " + party
		return "People have been pointing at %s over %s." % [who, matter]
	push_error("summary_text: unknown kind " + kind)
	return ""
