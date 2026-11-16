## Packaging a Godot-made case as a ``.mcase`` file (mirrors mystery/cases/package.py, Pilot 4B).
##
## The same format the bundled and imported cases use (docs/case-format.md), read by the same loader
## (core/case_format.gd): the player-safe investigation, the truth sealed with ``sha256-ctr-xor/1`` (a spoiler guard,
## not secrecy), one sealed relevance verdict per item for Hobby Detective checks, and spoiler-free summary and
## generator metadata from which the case can be made again. Everything is written as ASCII JSON with sorted keys, so
## the same seed gives the same bytes on every platform.
extends RefCounted

const CaseFormat = preload("res://scripts/core/case_format.gd")

const FORMAT_VERSION := 1
const TOOL := "mystery (Godot)"
const SIM_VERSION := "godot-native"
const CONFIG_VERSION := "godot-native"
const REL_WIDTH := 24
const DIFFICULTY := {"obvious": "gentle", "playable": "standard", "ambiguous": "hard", "unsolvable": "very hard"}
const SEASONS := {"normal": "An ordinary season", "scarcity": "A lean season", "crisis": "Hard times",
		"tension": "A troubled season"}


# ----------------------------------------------------------------------------- JSON
static func ascii_json(value, indent := "") -> String:
	## JSON with sorted keys and every non-ASCII character escaped (\uXXXX), as Python's ensure_ascii writes it: the
	## seal is opened with get_string_from_ascii, and the file reads the same on every platform.
	return escape_non_ascii(JSON.stringify(value, indent, true))


static func escape_non_ascii(text: String) -> String:
	var rx := RegEx.new()
	rx.compile("[^\\x{00}-\\x{7F}]")
	var found := rx.search_all(text)
	if found.is_empty():
		return text
	var out := PackedStringArray()
	var at := 0
	for m in found:
		out.append(text.substr(at, m.get_start() - at))
		var code: int = text.unicode_at(m.get_start())
		if code > 0xFFFF:
			code -= 0x10000
			out.append("\\u%04x\\u%04x" % [0xD800 + (code >> 10), 0xDC00 + (code & 0x3FF)])
		else:
			out.append("\\u%04x" % code)
		at = m.get_end()
	out.append(text.substr(at))
	return "".join(out)


# ----------------------------------------------------------------------------- seals
static func seal(truth: Dictionary, case_id: String) -> Dictionary:
	## Opened by CaseFormat.unseal (and by Python's package.unseal): the canonical JSON XORed with SHA-256 blocks of
	## "<salt>|<case id>|<counter>", base64.
	var plain := ascii_json(truth).to_ascii_buffer()
	var cipher := PackedByteArray()
	cipher.resize(plain.size())
	var pos := 0
	var counter := 0
	while pos < plain.size():
		var block := CaseFormat._keystream_block(case_id, counter)
		for i in range(block.size()):
			if pos >= plain.size():
				break
			cipher[pos] = plain[pos] ^ block[i]
			pos += 1
		counter += 1
	var data := Marshalls.raw_to_base64(cipher)
	return {"scheme": CaseFormat.SEAL_SCHEME, "length": plain.size(), "plain_sha256": CaseFormat.sha256_hex(plain),
			"data_sha256": data.sha256_text(), "data": data}


static func seal_item(value: String, case_id: String, ref: String) -> String:
	## One relevance verdict, "<verdict>|<reason>" padded to 24 characters, XORed with SHA-256 of the case id and
	## the item's id (CaseFormat.open_relevance opens exactly one).
	var plain := value.rpad(REL_WIDTH).to_ascii_buffer()
	var key := ("%s|%s|%s" % [CaseFormat.REL_SALT, case_id, ref]).sha256_buffer()
	var out := PackedByteArray()
	out.resize(plain.size())
	for i in range(plain.size()):
		out[i] = plain[i] ^ key[i]
	return Marshalls.raw_to_base64(out)


static func seal_relevance(relevance: Dictionary, case_id: String) -> Dictionary:
	var refs: Array = relevance.keys()
	refs.sort()
	var items := {}
	for ref in refs:
		var v: Dictionary = relevance[ref]
		items[ref] = seal_item("%s|%s" % [v["verdict"], v["reason"]], case_id, String(ref))
	return {"scheme": CaseFormat.REL_SCHEME, "items": items}


# ----------------------------------------------------------------------------- build
static func difficulty(report: Dictionary) -> String:
	## From how well the case can be worked out (package.py difficulty): a case with no route to the answer through
	## evidence is hard however many people point at the right person.
	var label: String = DIFFICULTY[report["verdict"]]
	if report.get("solvable_by_evidence") == false and label in ["gentle", "standard"]:
		return "hard"
	return label


static func build(case_: Dictionary) -> Dictionary:
	## The package as a dictionary, from a case made by case_builder.gd (investigation, truth with its suitability
	## report and relevance verdicts).
	var inv: Dictionary = case_["investigation"]
	var truth: Dictionary = case_["truth"]
	var cfg: Dictionary = truth["config"]
	var case_id: String = inv["case_id"]
	return {
		"format": CaseFormat.FORMAT,
		"format_version": FORMAT_VERSION,
		"case_id": case_id,
		"generator": {
			"tool": TOOL, "sim_version": SIM_VERSION, "config_version": CONFIG_VERSION,
			"seed": int(cfg["seed"]), "profile": cfg["profile"], "days": int(cfg["days"]), "residents": int(cfg["residents"]),
			"incident": truth["incident"]["id"], "event_log_digest": truth["event_log_digest"],
			# what else shaped the town: to make the case again, run the same configuration
			"options": {"memory": cfg["memory"], "crime": cfg["crime"], "violence": cfg["violence"],
					"shop_self_service": cfg["shop_self_service"]},
		},
		"summary": {
			"title": inv["hook"]["title"], "town": inv["town"], "start_label": inv["start_label"],
			"season": SEASONS.get(cfg["profile"], cfg["profile"]), "difficulty": difficulty(truth["suitability"]),
		},
		"investigation": inv,
		"sealed_truth": seal(truth, case_id),
		"relevance": seal_relevance(truth.get("relevance", {}), case_id),
	}


static func to_text(pkg: Dictionary) -> String:
	## The file's contents, as package.py write_package writes them (sorted keys, one-space indent, ASCII, final
	## newline).
	return ascii_json(pkg, " ") + "\n"


static func file_name(case_id: String) -> String:
	return case_id + CaseFormat.EXTENSION


static func write(file_text: String, case_id: String, out_dir: String) -> String:
	## Writes <out_dir>/<case id>.mcase and returns its path, or "" if it could not be written.
	var dir := out_dir if out_dir.ends_with("/") else out_dir + "/"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + file_name(case_id)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(file_text)
	f.close()
	return path
