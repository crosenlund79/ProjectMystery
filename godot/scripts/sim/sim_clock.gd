## Simulation time and calendar (mirrors mystery/sim/clock.py). ``t`` is minutes since Day 1 00:00; one
## tick is one hour. Day 1 is a Monday and every Sunday is a rest day.
extends RefCounted

const DAY := 1440
const TICK := 60
const WEEKDAYS := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


@warning_ignore("integer_division")
static func day_of(t: int) -> int:
	return t / DAY + 1


@warning_ignore("integer_division")
static func hour_of(t: int) -> int:
	return (t % DAY) / 60


static func weekday_of(t: int) -> int:
	return (day_of(t) - 1) % 7


static func weekday_name(t: int) -> String:
	return WEEKDAYS[weekday_of(t)]


static func is_rest_day(t: int) -> bool:
	return weekday_of(t) == 6


static func is_dark(t: int) -> bool:
	var h := hour_of(t)
	return h >= 20 or h < 6


static func at(day: int, hour: int, minute := 0) -> int:
	return (day - 1) * DAY + hour * 60 + minute


static func fmt(t: int) -> String:
	return "Day %d %02d:%02d" % [day_of(t), hour_of(t), t % 60]


static func fmt_clock(t: int) -> String:
	return "%02d:%02d" % [hour_of(t), t % 60]


static func date(t: int) -> String:
	## The calendar line: "Wednesday, Day 3".
	return "%s, Day %d" % [weekday_name(t), day_of(t)]
