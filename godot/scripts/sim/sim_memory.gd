## What residents believe, kept apart from what happened (mirrors mystery/sim/memory.py).
##
## The event log is the truth. A belief is never the truth itself: it is a claim one resident holds, with
## where it came from (``source``: self, saw, heard, told, inferred), when they got it, how sure they are and
## how much it matters to them. It points back to what it came from, so every claim can be audited:
##   event     the event it was perceived from (or the chat it was heard in); developer-only
##   told_by   who said it, and via the speaker's own belief it was copied from
##   premises  for an inference, the beliefs it was drawn from
##   error     developer-only: misidentified, time_distorted, certainty_inflated ...
## Nothing in a belief is read from the truth after it is formed.
##
## A claim: {kind, subject, other, location, start, end, detail, amount, obj, hedged}; absent values are null
## (Python's None). ``hedged`` means the holder is unsure who ``subject`` was.
## A belief: {id, holder, claim, source, acquired, confidence, salience, event, told_by, via, premises, error,
## told_to}.
extends RefCounted

const DAY := 1440
const SOURCE_RANK := {"self": 5, "saw": 4, "heard": 3, "told": 2, "inferred": 1}
const SALIENCE := {
	"presence": 0.12, "sighting": 0.3, "purchase": 0.2, "intoxicated": 0.3, "noise": 0.55,
	"loan": 0.6, "refusal": 0.6, "hardship": 0.5, "debt": 0.9, "grudge": 0.9, "argument": 0.65,
	"assault": 0.95, "loss": 0.95, "damage": 0.8, "vehicle_damage": 0.7, "injury": 0.85,
	"struck": 0.95, "fall": 0.9, "death": 1.0, "suspect": 0.75, "repair": 0.6, "theft_self": 1.0,
	"collision_self": 1.0, "drove": 0.35, "help": 0.5, "laid_off": 0.9, "confession": 1.0,
	"stash": 1.0, "treated": 0.6, "rent_missed": 0.6, "missing": 0.9,
}
## Claim kinds worth passing on in conversation.
const GOSSIP_KINDS := ["loss", "damage", "injury", "death", "argument", "assault", "debt", "hardship", "refusal",
		"suspect", "laid_off", "confession", "vehicle_damage", "grudge", "rent_missed", "struck", "missing"]
const INCIDENT_KINDS := ["loss", "damage", "injury", "death", "struck", "fall"]
const CLAIM_FIELDS := ["kind", "subject", "other", "location", "start", "end", "detail", "amount", "obj", "hedged"]

var holder := ""
var beliefs := []
var by_key := {}
var by_kind := {}
var open_presence := {}  # "subject|place" -> the presence belief still being extended


func _init(who: String) -> void:
	holder = who


static func claim(kind: String, fields := {}) -> Dictionary:
	var c := {"kind": kind, "subject": null, "other": null, "location": null, "start": null, "end": null,
			"detail": "", "amount": null, "obj": null, "hedged": false}
	for k in fields:
		c[k] = fields[k]
	return c


static func _part(v) -> String:
	return "~" if v == null else str(v)


static func key(c: Dictionary) -> String:
	## Two claims are "the same thing" when they agree on these, with the start time to the hour.
	var hour = null if c["start"] == null else floori(c["start"] / 60.0)
	return "|".join(PackedStringArray([c["kind"], _part(c["subject"]), _part(c["other"]), _part(c["location"]),
			_part(hour), c["detail"], _part(c["obj"])]))


func add(b: Dictionary) -> void:
	beliefs.append(b)
	by_key[key(b["claim"])] = b
	var kind: String = b["claim"]["kind"]
	if not by_kind.has(kind):
		by_kind[kind] = []
	by_kind[kind].append(b)


func find(c: Dictionary):
	return by_key.get(key(c))


func of_kind(kinds: Array, since = null) -> Array:
	var out := []
	for kind in kinds:
		for b in by_kind.get(kind, []):
			if since == null or b["acquired"] >= since:
				out.append(b)
	if kinds.size() > 1:
		out.sort_custom(func(a, b): return a["id"] < b["id"])
	return out


# ---------------------------------------------------------------- forgetting
static func retention_days(salience: float) -> float:
	if salience >= 0.9:
		return 10000.0
	return 1.5 + salience * 25.0


static func recall(b: Dictionary, now: int, anchors := []) -> Array:
	## [still remembered at ``now``, with what confidence]. ``anchors`` are [from, to] windows the holder has
	## reason to go over again (an incident they know about); memories inside them are kept as if salient.
	var sal: float = b["salience"]
	var c: Dictionary = b["claim"]
	var when: int = c["start"] if c["start"] != null else b["acquired"]
	for a in anchors:
		if a[0] - 8 * 60 <= when and when <= a[1] + 8 * 60:
			sal = maxf(sal, 0.75)
			break
	var age_days := maxf(0.0, (now - b["acquired"]) / float(DAY))
	if age_days > retention_days(sal):
		return [false, 0.0]
	var conf: float = b["confidence"] * maxf(0.35, 1.0 - age_days * 0.06 * (1.0 - sal))
	return [true, snappedf(conf, 0.001)]


static func recollect(b: Dictionary, now: int, rng) -> Dictionary:
	## How a remembered claim comes back at ``now`` (mystery/cases/export.py, _recalled): an everyday sighting
	## more than 20 minutes old that never mattered much may come back 30 to 60 minutes off. ``rng`` is a
	## stream for this belief and this moment of recall, so the same question gets the same answer.
	var c: Dictionary = b["claim"].duplicate()
	if (now - b["acquired"] > 20 * 60 and b["salience"] < 0.9 and c["start"] != null
			and c["kind"] in ["presence", "sighting", "noise", "intoxicated"]):
		if rng.random() < 0.3:
			var shift: int = rng.choice([-60, -45, -30, 30, 45, 60])
			c["start"] += shift
			if c["end"] != null:
				c["end"] += shift
			return {"claim": c, "error": "misremembered_time"}
	return {"claim": c, "error": null}
