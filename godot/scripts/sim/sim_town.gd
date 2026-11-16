## Seeded town generation (mirrors generate_town in mystery/sim/residents.py): places and walking times,
## households and homes, residents with roles, wages, cash, needs and personality traits, the businesses'
## containers and books, vehicles, relationships, old grudges and starting debts.
extends RefCounted

const SimRng = preload("res://scripts/sim/sim_rng.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Config = preload("res://scripts/sim/sim_config.gd")
const World = preload("res://scripts/sim/sim_world.gd")
const Resident = preload("res://scripts/sim/sim_resident.gd")

const FIRST_NAMES := [
	"Daniel", "Margaret", "Elias", "Ruth", "Tomas", "Agnes", "Felix", "Ida", "Oskar", "Lena",
	"Henrik", "Vera", "Anton", "Clara", "Emil", "Greta", "Jonas", "Marta", "Viktor", "Nora",
	"Arvid", "Selma", "Bruno", "Hedda",
]
const SURNAMES := ["Harrow", "Lind", "Brandt", "Okafor", "Vale", "Morrow", "Kessler", "Dunmore", "Ash", "Pryce",
		"Holm", "Carver"]
const TOWN_NAMES := ["Kestrel Hollow", "Wyndmere", "Lowbridge", "Greyford", "Ashcombe", "Thornwick"]
const PUB_NAMES := ["the Lantern", "the Crooked Pike", "the Drover's Rest", "the Grey Heron"]
const GRUDGE_REASONS := [
	"a quarrel over a boundary fence",
	"an unpaid bill from last winter",
	"a broken engagement",
	"something said at the pub years ago",
	"a dog that was never returned",
]
const AGE_GROUPS := ["young adult", "adult", "middle-aged", "older"]
const ROLES := {
	"grocer": {"label": "grocer", "workplace": "grocery", "shift": [8, 18], "wage": 0},
	"publican": {"label": "publican", "workplace": "pub", "shift": [11, 23], "wage": 0},
	"mechanic": {"label": "mechanic", "workplace": "workshop", "shift": [8, 17], "wage": 18},
	"nurse": {"label": "nurse", "workplace": "clinic", "shift": [9, 17], "wage": 26},
	"mill_owner": {"label": "mill owner", "workplace": "mill", "shift": [7, 16], "wage": 0},
	"mill_hand": {"label": "mill hand", "workplace": "mill", "shift": [7, 16], "wage": 22},
	"shop_assistant": {"label": "shop assistant", "workplace": "grocery", "shift": [9, 17], "wage": 18},
	"barhand": {"label": "barhand", "workplace": "pub", "shift": [17, 23], "wage": 16},
	"unemployed": {"label": "out of work", "workplace": "", "shift": [], "wage": 0},
	"retiree": {"label": "retired", "workplace": "", "shift": [], "wage": 0},
}
const ROLE_SEQUENCE := ["grocer", "publican", "mechanic", "nurse", "mill_owner", "mill_hand", "mill_hand",
		"unemployed", "shop_assistant", "barhand", "retiree", "mill_hand"]
const START_CASH := {
	"grocer": [60, 120], "publican": [60, 120], "mechanic": [40, 100], "nurse": [50, 110],
	"mill_owner": [120, 250], "mill_hand": [20, 70], "shop_assistant": [20, 60],
	"barhand": [15, 50], "unemployed": [5, 30], "retiree": [30, 80],
}


static func _r3(x: float) -> float:
	return snappedf(x, 0.001)


static func generate(cfg: Dictionary) -> Dictionary:
	## {"world", "residents": {id: Resident}, "meta": {households, heads, landlord, grudges, initial_debts}}
	var rng := SimRng.new([cfg["seed"], "town", cfg["profile"], cfg["residents"]])
	var prof := Config.profile(cfg["profile"])
	var n: int = cfg["residents"]
	var world := World.new(rng.choice(TOWN_NAMES), rng.choice(PUB_NAMES))

	world.add_location("square", "the square", "square", {"outdoor": true})
	world.add_location("road", "Mill Road", "road", {"outdoor": true})
	world.add_location("grocery", "the grocery", "shop", {"hours": [8, 18], "lockable": true})
	world.add_location("pub", world.pub_name, "pub", {"hours": [11, 23], "lockable": true})
	world.add_location("workshop", "the workshop", "workshop", {"hours": [8, 17], "lockable": true})
	world.add_location("clinic", "the clinic", "clinic", {"hours": [9, 17], "lockable": true})
	world.add_location("mill", "the mill", "mill", {"hours": [7, 16], "lockable": true})
	for pm in [["grocery", 2], ["pub", 2], ["workshop", 3], ["clinic", 3], ["road", 6]]:
		world.connect_places("square", pm[0], pm[1])
	world.connect_places("road", "mill", 6)

	var roles := ROLE_SEQUENCE.slice(0, n)
	var firsts := rng.sample(FIRST_NAMES, n)
	var order := range(n)
	rng.shuffle(order)
	var groups := []
	var i := 0
	while i < n:
		var size := 2 if (n - i >= 2 and rng.random() < 0.45) else 1
		groups.append(order.slice(i, i + size))
		i += size
	var surnames := rng.sample(SURNAMES, groups.size())

	var residents := {}
	var households := {}
	for gi in groups.size():
		var surname: String = surnames[gi]
		var hid := surname.to_lower()
		var home := "home:" + hid
		var outskirts := gi % 2 == 1
		world.add_location(home, "the %s house" % surname, "home", {"household": hid, "lockable": true})
		world.connect_places("road" if outskirts else "square", home, 5 if outskirts else 4)
		households[hid] = []
		for idx in groups[gi]:
			var role: String = roles[idx]
			var info: Dictionary = ROLES[role]
			var t := {}
			for name in Resident.TRAITS:
				t[name] = _r3(clampf(rng.beta22(), 0.0, 1.0))
			t["temperance"] = _r3(clampf(t["temperance"] - (prof["drink_mult"] - 1.0) * 0.35, 0.0, 1.0))
			t["impulsiveness"] = _r3(clampf(t["impulsiveness"] + prof["impulsive_shift"], 0.0, 1.0))
			if role == "nurse":
				t["empathy"] = _r3(clampf(t["empathy"] + 0.2, 0.0, 1.0))
			if role == "publican":
				t["sociability"] = _r3(clampf(t["sociability"] + 0.2, 0.0, 1.0))
			var r := Resident.new()
			r.first = firsts[idx]
			r.id = r.first.to_lower()
			r.last = surname
			r.age_group = rng.choice(AGE_GROUPS) if role != "retiree" else "older"
			r.role = role
			r.occupation = info["label"]
			r.household = hid
			r.home = home
			r.workplace = info["workplace"]
			r.shift = info["shift"].duplicate()
			r.wage = int(round(info["wage"] * prof["wage_mult"]))
			r.traits = t
			r.cash = rng.randint(START_CASH[role][0], START_CASH[role][1])
			r.employed = info["workplace"] != ""
			r.hunger = rng.uniform(10, 40)
			r.energy = rng.uniform(70, 95)
			r.social = rng.uniform(40, 80)
			residents[r.id] = r
			households[hid].append(r.id)

	var ids := residents.keys()
	ids.sort()
	var by_role := {}
	for rid in ids:
		var role_name: String = residents[rid].role
		if not by_role.has(role_name):
			by_role[role_name] = []
		by_role[role_name].append(rid)

	for pr in [["grocery", "grocer"], ["pub", "publican"], ["workshop", "mechanic"], ["clinic", "nurse"],
			["mill", "mill_owner"]]:
		world.locations[pr[0]]["owners"] = by_role.get(pr[1], []).duplicate()
		var staff := []
		for rid in ids:
			if residents[rid].workplace == pr[0]:
				staff.append(rid)
		world.locations[pr[0]]["staff"] = staff
	for hid in households:
		world.locations["home:" + hid]["owners"] = households[hid].duplicate()

	world.add_container("till:grocery", "grocery", "the grocery till", by_role["grocer"], rng.randint(60, 120))
	world.add_container("stock:grocery", "grocery", "the grocery stock room", by_role["grocer"], 0, 160)
	world.add_container("till:pub", "pub", "the till at " + world.pub_name, by_role["publican"], rng.randint(80, 150))
	world.add_container("cashbox:mill", "mill", "the mill cashbox", by_role["mill_owner"], 400)
	for hid in households:
		var members: Array = households[hid]
		var last: String = residents[members[0]].last
		world.add_container("box:" + hid, "home:" + hid, "the %s household savings tin" % last, members,
				rng.randint(20, 150))
		world.add_container("pantry:" + hid, "home:" + hid, "the %s pantry" % last, members, 0, rng.randint(6, 14))

	world.add_book("ledger", "grocery", "Grocery sales ledger")
	world.add_book("tabs", "pub", "Bar tab book at " + world.pub_name)
	world.add_book("clinic_log", "clinic", "Clinic patient log")
	world.add_book("workshop_orders", "workshop", "Workshop job book")

	var mech: Object = residents[by_role["mechanic"][0]]
	_give_vehicle(world, residents, households, "truck", "the rust-red workshop truck", "truck", mech.household)
	var owner: Object = residents[by_role["mill_owner"][0]]
	if owner.household != mech.household:
		_give_vehicle(world, residents, households, "saloon", "the grey saloon car", "car", owner.household)
	if n >= 10:
		var hids := households.keys()
		hids.sort()
		for hid in hids:
			var home: Dictionary = world.locations["home:" + hid]
			if home["adj"].has("road") and residents[households[hid][0]].vehicle == "":
				_give_vehicle(world, residents, households, "hatchback", "the old blue hatchback", "car", hid)
				break

	# relationships
	for a in ids:
		for b in ids:
			if a == b:
				continue
			var ra = residents[a]
			var rb = residents[b]
			var rel: Dictionary = ra.r(b)
			if ra.household == rb.household:
				rel["trust"] = 0.85
				rel["affection"] = 0.8
			else:
				rel["trust"] = _r3(rng.uniform(0.35, 0.7))
				rel["affection"] = _r3(rng.uniform(0.2, 0.6))
				rel["resentment"] = _r3(rng.uniform(0.0, 0.1))
				if ra.workplace != "" and ra.workplace == rb.workplace:
					rel["trust"] = _r3(minf(1.0, rel["trust"] + 0.1))

	var grudges := []
	var candidates := []
	for a in ids:
		for b in ids:
			if a < b and residents[a].household != residents[b].household:
				candidates.append([a, b])
	for pair in rng.sample(candidates, mini(prof["grudge_pairs"], candidates.size())):
		var a: String = pair[0]
		var b: String = pair[1]
		var reason: String = rng.choice(GRUDGE_REASONS)
		residents[a].r(b)["resentment"] = _r3(rng.uniform(0.45, 0.7))
		residents[b].r(a)["resentment"] = _r3(rng.uniform(0.3, 0.6))
		residents[a].r(b)["trust"] = 0.25
		residents[b].r(a)["trust"] = 0.25
		grudges.append({"a": a, "b": b, "reason": reason})

	var debts := []
	for rid in ids:
		if rng.random() >= prof["initial_debt_rate"]:
			continue
		var r = residents[rid]
		var lenders := []
		for x in ids:
			if residents[x].household != r.household and residents[x].cash > r.cash:
				lenders.append(x)
		if lenders.is_empty():
			continue
		var lender: String = rng.choice(lenders)
		debts.append({"debtor": rid, "creditor": lender, "amount": rng.randint(30, 90),
				"due": SimClock.at(rng.randint(3, 12), 18)})

	var heads := {}
	for hid in households:
		heads[hid] = households[hid][0]
	return {"world": world, "residents": residents, "meta": {"households": households, "heads": heads,
			"landlord": by_role["mill_owner"][0], "grudges": grudges, "initial_debts": debts}}


static func _give_vehicle(world, residents: Dictionary, households: Dictionary, vid: String, name: String,
		kind: String, hid: String) -> void:
	world.vehicles[vid] = {"id": vid, "name": name, "kind": kind, "household": hid, "location": "home:" + hid,
			"damage": "", "damage_event": "", "damage_evidence": ""}
	for rid in households[hid]:
		residents[rid].vehicle = vid
