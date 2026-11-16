## Seasons ("profiles"), prices and run settings (mirrors mystery/sim/config.py). The values are the
## Python values: change them in both places or the two simulations stop being comparable.
extends RefCounted

const DEFAULT_PROFILE := {
	"wage_mult": 1.0, "food_price": 4, "delivery_units": 150, "initial_debt_rate": 0.25, "grudge_pairs": 1,
	"drink_mult": 1.0, "impulsive_shift": 0.0, "layoffs": 0,
	"mill_margin": 45,  # the mill's daily profit over the wages it pays
	"odd_jobs": 0.8,  # chance a day's casual work is available at the mill
}
const PROFILES := {
	"normal": {"description": "An ordinary autumn with modest margins."},
	"scarcity": {"description": "Supply shortages: food is dear and deliveries arrive short.",
			"food_price": 6, "delivery_units": 55},
	"crisis": {"description": "Economic downturn: wages cut, a mill hand laid off, more people in debt.",
			"wage_mult": 0.7, "initial_debt_rate": 0.5, "layoffs": 1, "mill_margin": -5, "odd_jobs": 0.3},
	"tension": {"description": "Old grudges, heavy drinking and short tempers.",
			"grudge_pairs": 3, "drink_mult": 1.5, "impulsive_shift": 0.12},
}

# Prices and amounts, in crowns.
const DRINK_PRICE := 3
const DRINK_COST := 1
const PUB_MEAL_PRICE := 9
const PUB_MEAL_COST := 4
const RENT := 40
const PENSION_WEEKLY := 110
const TILL_FLOAT := {"grocery": 250, "pub": 60}
const ODD_JOB_PAY := 12
const SUPPLIER_COST_RATIO := 0.6
const STOCK_CAPACITY := 220


static func profile(name: String) -> Dictionary:
	var p := DEFAULT_PROFILE.duplicate()
	p.merge(PROFILES[name], true)
	p["name"] = name
	return p


static func normalize(cfg: Dictionary) -> Dictionary:
	## {"seed": int, "days": 60, "profile": "normal", "residents": 10, "memory": true, "crime": false}, defaults
	## filled in.
	## memory: residents perceive, remember and gossip (Pilot 2). false runs Pilot 1's town exactly, as it was
	## before memory existed (its pinned histories still hold).
	## crime: Python's whole crime layer. Off by default: with it off, the town lives exactly as it did before
	## (Pilot 1 and 2 histories hold). On, it brings ledger mistakes, theft, hidden loot, discovered losses,
	## evidence and the incident registry (Pilot 3A), and with violence (default true) fights, injuries and
	## deaths, drunken falls, collisions on Mill Road, the clinic, repairs, and people found or missed (Pilot 3B).
	## crime with violence false is Pilot 3A exactly (its pinned histories hold).
	return {"seed": int(cfg.get("seed", 1)), "days": int(cfg.get("days", 60)),
			"profile": String(cfg.get("profile", "normal")), "residents": int(cfg.get("residents", 10)),
			"memory": bool(cfg.get("memory", true)), "crime": bool(cfg.get("crime", false)),
			"violence": bool(cfg.get("violence", true))}


static func problem(cfg: Dictionary) -> String:
	## Why a configuration cannot run, or "".
	if not PROFILES.has(cfg["profile"]):
		return "unknown profile %s; choose from %s" % [cfg["profile"], PROFILES.keys()]
	if cfg["residents"] < 8 or cfg["residents"] > 12:
		return "residents must be between 8 and 12 for this prototype"
	if cfg["days"] < 1:
		return "days must be positive"
	if cfg["crime"] and not cfg["memory"]:
		return "crime needs memory: who discovers a loss, who suspects whom, what a thief conceals"
	return ""
