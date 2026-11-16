## One resident (mirrors the Resident dataclass in mystery/sim/residents.py). Needs run 0-100; traits and
## relationship values run 0-1. Injury, death and guilt fields belong to the crime layer and are not here yet.
extends RefCounted

const TRAITS := ["impulsiveness", "caution", "empathy", "honesty", "sociability", "stubbornness", "temperance",
		"diligence"]

var id := ""
var first := ""
var last := ""
var age_group := ""
var role := ""
var occupation := ""
var household := ""
var home := ""
var workplace := ""  # "" when they have no workplace
var shift := []  # [start hour, end hour), or [] with no job
var wage := 0
var traits := {}
var cash := 0
var hunger := 25.0
var energy := 85.0
var social := 60.0
var stress := 10.0
var intox := 0.0
var asleep := true
var alive := true
var down := false
var employed := true
var rel := {}  # other id -> {trust, affection, resentment}
var vehicle := ""
var pressures := []  # [time, event id] of things that went wrong for them
var cooldowns := {}  # key -> minute until which they won't try that again
var worked_today := false


func full_name() -> String:
	return "%s %s" % [first, last]


func r(other: String) -> Dictionary:
	if not rel.has(other):
		rel[other] = {"trust": 0.5, "affection": 0.4, "resentment": 0.0}
	return rel[other]


func to_dict() -> Dictionary:
	return {"id": id, "name": full_name(), "age_group": age_group, "role": role, "occupation": occupation,
			"household": household, "home": home, "workplace": workplace, "shift": shift, "wage": wage,
			"traits": traits, "cash": cash, "hunger": snappedf(hunger, 0.01), "energy": snappedf(energy, 0.01),
			"social": snappedf(social, 0.01), "stress": snappedf(stress, 0.01), "intox": snappedf(intox, 0.01),
			"asleep": asleep, "employed": employed, "vehicle": vehicle, "rel": rel}
