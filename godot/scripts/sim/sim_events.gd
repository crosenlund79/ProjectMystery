## The factual, chronological record of what happened (mirrors mystery/sim/events.py).
##
## An event: {id, seq, time, location, kind, actors, targets, objects, data, causes, intent, audibility,
## notable, summary}. Ids follow the order events are created in (E000001, ...), so a cause always has a
## smaller id than its effect. Within one hour, effects are timed a minute or two after their causes, so the
## log is kept in time order: events of an hour are held until the hour ends, then added sorted by time
## (ties keep creation order).
extends RefCounted

var events := []
var by_id := {}
var _pending := []
var _seq := 0


func next_id() -> String:
	return "E%06d" % (_seq + 1)


func add(ev: Dictionary) -> Dictionary:
	_seq += 1
	ev["seq"] = _seq
	ev["id"] = "E%06d" % _seq
	_pending.append(ev)
	by_id[ev["id"]] = ev
	return ev


func _earlier(a: Dictionary, b: Dictionary) -> bool:
	if a["time"] != b["time"]:
		return a["time"] < b["time"]
	return a["seq"] < b["seq"]


func commit() -> void:
	## End of an hour: its events join the log in time order.
	_pending.sort_custom(_earlier)
	events.append_array(_pending)
	_pending.clear()


func size() -> int:
	return events.size() + _pending.size()


func counts() -> Dictionary:
	var out := {}
	for ev in events:
		out[ev["kind"]] = int(out.get(ev["kind"], 0)) + 1
	return out


static func line(ev: Dictionary) -> String:
	## One event as canonical JSON: sorted keys, so the digest does not depend on how it was built.
	return JSON.stringify(ev, "", true)


func digest() -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for ev in events:
		h.update((line(ev) + "\n").to_utf8_buffer())
	return h.finish().hex_encode()
