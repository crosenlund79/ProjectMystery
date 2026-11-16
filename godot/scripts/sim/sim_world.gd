## Places, containers, vehicles, record books, debts, physical evidence and the money/food ledger (mirrors
## mystery/sim/world.py).
##
## Plain dictionaries, keyed by id, in insertion order (deterministic):
##   location  {id, name, kind, outdoor, hours: [open, close) or [], owners, staff, household, lockable, locked,
##              adj: {neighbour: walking minutes}}
##   container {id, location, label, owners, cash, food, hidden, expected_cash, expected_food, last_check,
##              unexplained: events that changed it unseen since it was last counted (a theft, a ledger mistake)}
##   vehicle   {id, name, kind, household, location, damage, damage_event, damage_evidence} ("" when undamaged)
##   debt      {id, debtor, creditor, amount, due, created, origin_event, kind, settled, settled_event,
##              overdue_event}; settled = -1 while open
##   transfer  {time, event, asset, src, dst, amount}
##   evidence  {id, kind, place, description, created_at, created_by (event id), removed_at, removed_by
##              (-1 / "" while present), implicates (developer-only), noticed_by, glimpse}: a physical trace,
##              which exists only because an event made it (crime layer, Pilot 3A)
extends RefCounted

var town_name := ""
var pub_name := ""
var locations := {}
var containers := {}
var vehicles := {}
var books := {}
var records := {}
var debts := []
var transfers := []
var evidence := []
var _paths := {}
var _hops := {}


func _init(town: String, pub: String) -> void:
	town_name = town
	pub_name = pub


func add_location(id: String, name: String, kind: String, extra := {}) -> void:
	var loc := {"id": id, "name": name, "kind": kind, "outdoor": false, "hours": [], "owners": [], "staff": [],
			"household": "", "lockable": false, "locked": false, "adj": {}}
	loc.merge(extra, true)
	locations[id] = loc


func connect_places(a: String, b: String, minutes: int) -> void:
	locations[a]["adj"][b] = minutes
	locations[b]["adj"][a] = minutes


static func is_open(loc: Dictionary, hour: int) -> bool:
	var hours: Array = loc["hours"]
	if hours.is_empty():
		return true
	return hours[0] <= hour and hour < hours[1]


func path(a: String, b: String) -> Array:
	## Breadth-first, neighbours in sorted order: the same route every time.
	var key := a + ">" + b
	if not _paths.has(key):
		var prev := {a: ""}
		var queue := [a]
		var head := 0
		while head < queue.size():
			var cur: String = queue[head]
			head += 1
			if cur == b:
				break
			var nexts: Array = locations[cur]["adj"].keys()
			nexts.sort()
			for nxt in nexts:
				if not prev.has(nxt):
					prev[nxt] = cur
					queue.append(nxt)
		var nodes := [b]
		while prev[nodes[-1]] != "":
			nodes.append(prev[nodes[-1]])
		nodes.reverse()
		_paths[key] = nodes
	return _paths[key]


func hops(a: String, b: String) -> int:
	## Steps between two places on the map (99 if unconnected): how far a sound carries.
	if not _hops.has(a):
		var dist := {a: 0}
		var queue := [a]
		var head := 0
		while head < queue.size():
			var cur: String = queue[head]
			head += 1
			var nexts: Array = locations[cur]["adj"].keys()
			nexts.sort()
			for nxt in nexts:
				if not dist.has(nxt):
					dist[nxt] = dist[cur] + 1
					queue.append(nxt)
		_hops[a] = dist
	return int(_hops[a].get(b, 99))


func name_of(id: String) -> String:
	if locations.has(id):
		return locations[id]["name"]
	if vehicles.has(id):
		return vehicles[id]["name"]
	return id


func add_container(id: String, location: String, label: String, owners: Array, cash := 0, food := 0) -> void:
	containers[id] = {"id": id, "location": location, "label": label, "owners": owners.duplicate(), "cash": cash,
			"food": food, "hidden": false, "expected_cash": cash, "expected_food": food, "last_check": 0,
			"unexplained": []}


func add_book(book: String, place: String, title: String) -> void:
	books[book] = {"place": place, "title": title}
	records[book] = []


func record(book: String, time: int, text: String, event_id: String) -> Dictionary:
	var entry := {"id": "%s#%d" % [book, records[book].size() + 1], "book": book, "time": time, "text": text,
			"event": event_id}
	records[book].append(entry)
	return entry


func add_debt(debtor: String, creditor: String, amount: int, due: int, created: int, origin_event: String,
		kind := "loan") -> Dictionary:
	var d := {"id": "D%03d" % (debts.size() + 1), "debtor": debtor, "creditor": creditor, "amount": amount, "due": due,
			"created": created, "origin_event": origin_event, "kind": kind, "settled": -1, "settled_event": "",
			"overdue_event": ""}
	debts.append(d)
	return d


func add_evidence(kind: String, place: String, description: String, time: int, event_id: String, implicates := [],
		glimpse := "") -> Dictionary:
	var e := {"id": "X%04d" % (evidence.size() + 1), "kind": kind, "place": place, "description": description,
			"created_at": time, "created_by": event_id, "removed_at": -1, "removed_by": "",
			"implicates": implicates.duplicate(), "noticed_by": [], "glimpse": glimpse}
	evidence.append(e)
	return e


func present_at(e: Dictionary, t: int) -> bool:
	return e["created_at"] <= t and (e["removed_at"] < 0 or t < e["removed_at"])


func evidence_at(place: String, t: int) -> Array:
	var out := []
	for e in evidence:
		if e["place"] == place and present_at(e, t):
			out.append(e)
	return out


func debt(id: String) -> Dictionary:
	for d in debts:
		if d["id"] == id:
			return d
	return {}


func to_dict() -> Dictionary:
	return {"town": town_name, "pub": pub_name, "locations": locations, "vehicles": vehicles, "books": books}
