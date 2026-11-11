## The world layer: where the player is, who can be found where, and what each place holds.
##
## People are where the simulation left them at the frozen instant the case begins
## (investigation.residents[].now_at, schema 0.2). That is present state anyone could see by
## walking around town, not the past. Older packages without it fall back to "at home".
## The player learns where someone is by going there and seeing them. Talking needs the person to
## be present; record books are read where they are kept; vehicles are examined where they are
## parked. The rules of questioning, permissions and evidence stay in investigation.gd.
##
## This model works only on the player-safe investigation view. It never reads the sealed truth.
extends RefCounted

var engine
var data: Dictionary
var ui: Dictionary
var _places := {}
var _now := {}


func _init(engine_) -> void:
	engine = engine_
	data = engine.data
	ui = engine.state["ui"]
	for p in data["places"]:
		_places[p["id"]] = p
	for r in data["residents"]:
		var loc = null
		if r["condition"] != "deceased":
			loc = r.get("now_at") if r.has("now_at") else r.get("home")
		_now[r["id"]] = loc if (loc != null and _places.has(loc)) else null
	for k in ["visited", "seen"]:
		if typeof(ui.get(k)) != TYPE_DICTIONARY:
			ui[k] = {}
	if not _places.has(String(ui.get("at", ""))):
		ui["at"] = ""


# --------------------------------------------------------------------------- lookups
func places() -> Array:
	return data["places"]


func place(pid: String) -> Dictionary:
	return _places.get(pid, {})


func has_place(pid: String) -> bool:
	return _places.has(pid)


func at() -> String:
	return String(ui.get("at", ""))


func arrived() -> bool:
	return at() != ""


func start_place() -> String:
	## Where the player arrives: the town square, or failing that the first public place.
	if _places.has("square"):
		return "square"
	for p in data["places"]:
		if p["owners"].is_empty():
			return p["id"]
	return data["places"][0]["id"]


func scene() -> String:
	return String(data["hook"]["place"])


func visited(pid: String) -> bool:
	return ui["visited"].has(pid)


func people_at(pid: String) -> Array:
	## Everyone who is at a place right now, alive, by name.
	var out := []
	for r in data["residents"]:
		if _now.get(r["id"]) == pid:
			out.append(r["id"])
	out.sort_custom(_by_name)
	return out


func _by_name(a, b) -> bool:
	return String(engine.resident(a).get("name", a)) < String(engine.resident(b).get("name", b))


func people_here() -> Array:
	return people_at(at()) if arrived() else []


func known_people_at(pid: String) -> Array:
	## The people the player has seen at a place (the map shows only what the player knows).
	var out := []
	for rid in people_at(pid):
		if ui["seen"].get(rid) == pid:
			out.append(rid)
	return out


func whereabouts(rid: String):
	## The place the player has seen this person at, or null if they do not know.
	return ui["seen"].get(rid)


func is_here(rid: String) -> bool:
	return arrived() and _now.get(rid) == at()


func records_at(pid: String) -> Array:
	var out := []
	for k in data["records"]:
		if data["records"][k]["place"] == pid:
			out.append(k)
	out.sort()
	return out


func record_place(book: String) -> String:
	return String(data["records"].get(book, {}).get("place", ""))


func vehicles_at(pid: String) -> Array:
	var out := []
	for v in data["vehicles"]:
		if v["location"] == pid:
			out.append(v["id"])
	out.sort()
	return out


# --------------------------------------------------------------------------- moving
func go(pid: String) -> Dictionary:
	if not _places.has(pid):
		return {"op": "go", "error": "There is no such place in town."}
	ui["at"] = pid
	var first := not ui["visited"].has(pid)
	ui["visited"][pid] = true
	var here := people_at(pid)
	for rid in here:
		ui["seen"][rid] = pid
	return {"op": "go", "place": pid, "first_visit": first, "present": here}


func find(rid: String) -> Dictionary:
	## Go to someone: where you last saw them if you know, otherwise try their home.
	var r: Dictionary = engine.resident(rid)
	if r.is_empty():
		return {"op": "find", "error": "There is nobody by that name in town."}
	if r["condition"] == "deceased":
		return {"op": "find", "who": rid, "found": false, "dead": true, "place": at(),
				"message": "%s is dead." % r["first"]}
	var known = whereabouts(rid)
	var target: String = known if known != null else String(r["home"])
	if not _places.has(target):
		return {"op": "find", "who": rid, "found": false, "place": at(),
				"message": "You don't know where to find %s." % r["first"]}
	go(target)
	var found: bool = _now.get(rid) == target
	var msg := ""
	if not found:
		msg = "%s isn't at %s. You'll have to look for them around town." % [r["first"], engine.place_name(target)]
	return {"op": "find", "who": rid, "place": target, "found": found, "known": known != null, "message": msg}


# --------------------------------------------------------------------------- acting where you are
func ask(rid: String, topic: String, press := false) -> Dictionary:
	## Questions need the person in front of you.
	if not is_here(rid):
		var r: Dictionary = engine.resident(rid)
		return {"op": "ask", "who": rid, "error": "%s isn't here." % r.get("first", "They")}
	return engine.ask(rid, topic, press)


func look_around() -> Dictionary:
	if not arrived():
		return {"op": "inspect_place", "error": "You are not anywhere yet."}
	return engine.inspect_place(at())


func read(book: String, day = null) -> Dictionary:
	## Record books are read where they are kept.
	if not data["records"].has(book):
		return {"op": "read", "error": "There is no such record book."}
	if record_place(book) != at():
		return {"op": "read", "book": book,
				"error": "The %s is kept at %s." % [String(data["records"][book]["title"]).to_lower(),
						engine.place_name(record_place(book))]}
	return engine.read(book, day)


func examine(vid: String) -> Dictionary:
	## Vehicles are examined where they are parked.
	if not vehicles_at(at()).has(vid):
		return {"op": "inspect_vehicle", "error": "That vehicle isn't parked here."}
	return engine.inspect_vehicle(vid)
