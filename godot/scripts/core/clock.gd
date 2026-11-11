## Simulation time helpers. ``t`` is minutes since Day 1 00:00 (the Python clock).
## Mirrors mystery/sim/clock.py; JSON numbers arrive as floats, so everything goes through int().
extends RefCounted

const DAY := 1440


static func idiv(a: int, b: int) -> int:
	return int(floor(float(a) / float(b)))


static func day_of(t) -> int:
	return idiv(int(t), DAY) + 1


static func fmt(t) -> String:
	var m := int(t)
	return "Day %d %02d:%02d" % [idiv(m, DAY) + 1, idiv(m % DAY, 60), m % 60]


static func clock(t) -> String:
	var m := int(t)
	return "%02d:%02d" % [idiv(m % DAY, 60), m % 60]


static func around(t) -> String:
	## "around 23:15 on Day 11" - every time a witness gives is approximate.
	var r := int(round(float(int(t)) / 15.0)) * 15
	return "around %s on Day %d" % [clock(r), day_of(r)]
