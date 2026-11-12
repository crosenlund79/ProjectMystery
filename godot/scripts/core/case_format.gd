## Reading, validating and unsealing ``.mcase`` packages (format: docs/case-format.md).
##
## Mirrors mystery/cases/package.py. The investigation part is player-safe; the truth stays
## sealed (base64 of the truth JSON XORed with a SHA-256 counter-mode keystream) until
## ``unseal`` is called, which only the reveal does. The seal is a spoiler guard, not
## secrecy: the scheme and salt are public.
extends RefCounted

const FORMAT := "project-mystery-case"
const SUPPORTED_VERSIONS := [1]
const SEAL_SCHEME := "sha256-ctr-xor/1"
const SEAL_SALT := "project-mystery case seal v1"
const EXTENSION := ".mcase"
const BASE_TOPICS := ["whereabouts", "window", "incident", "money", "conflicts", "rumors", "vehicles", "past"]
const SOURCES := ["self", "saw", "heard", "told", "inferred"]
const STYLES := ["nervous", "smooth"]
## Keys that would carry the truth. None may appear anywhere in the investigation view.
const FORBIDDEN_KEYS := ["intent", "causes", "status", "lie", "error", "implicates", "responsible", "event", "belief",
		"created_by", "supports", "accurate", "answer", "narrative", "chain", "guilty_of", "traits"]


static func load_file(path: String) -> Dictionary:
	## Returns {"ok": bool, "package": Dictionary or null, "errors": Array[String]}.
	if not FileAccess.file_exists(path):
		return {"ok": false, "package": null, "errors": ["File not found: %s" % path]}
	return parse_text(FileAccess.get_file_as_string(path))


static func parse_text(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {"ok": false, "package": null, "errors": ["The file is empty."]}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "package": null,
				"errors": ["Not a valid case file (JSON error on line %d: %s)." % [json.get_error_line(), json.get_error_message()]]}
	var problems := validate(json.data)
	if not problems.is_empty():
		return {"ok": false, "package": null, "errors": problems}
	return {"ok": true, "package": json.data, "errors": []}


# --------------------------------------------------------------------------- type checks
static func _is_int(v) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	return typeof(v) == TYPE_FLOAT and is_finite(v) and v == floor(v)


static func _ok(v, kind: String) -> bool:
	match kind:
		"str":
			return typeof(v) == TYPE_STRING
		"int":
			return _is_int(v)
		"bool":
			return typeof(v) == TYPE_BOOL
		"list":
			return typeof(v) == TYPE_ARRAY
		"dict":
			return typeof(v) == TYPE_DICTIONARY
		"int?":
			return v == null or _is_int(v)
		"str?":
			return v == null or typeof(v) == TYPE_STRING
	return false


static func _need(obj, key: String, kind: String, where: String, p: Array):
	if typeof(obj) != TYPE_DICTIONARY or not obj.has(key):
		p.append("%s: missing '%s'" % [where, key])
		return null
	var v = obj[key]
	if not _ok(v, kind):
		p.append("%s: '%s' should be %s" % [where, key, kind])
		return null
	return v


static func _list(v) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []


static func _dict(v) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}


# --------------------------------------------------------------------------- validation
static func spoiler_problems(investigation: Dictionary) -> Array:
	var p := []
	var keys := {}
	_collect_keys(investigation, keys)
	var leaked := []
	for k in FORBIDDEN_KEYS:
		if keys.has(k):
			leaked.append(k)
	if not leaked.is_empty():
		p.append("investigation view contains truth fields: %s" % [leaked])
	var text := JSON.stringify(investigation)
	var ev := RegEx.new()
	ev.compile("\\bE\\d{6}\\b")
	if ev.search(text) != null:
		p.append("investigation view contains event ids")
	var be := RegEx.new()
	be.compile("\\bB\\d{6}\\b")
	if be.search(text) != null:
		p.append("investigation view contains belief ids")
	return p


static func _collect_keys(obj, out: Dictionary) -> void:
	if typeof(obj) == TYPE_DICTIONARY:
		for k in obj:
			out[str(k)] = true
			_collect_keys(obj[k], out)
	elif typeof(obj) == TYPE_ARRAY:
		for v in obj:
			_collect_keys(v, out)


## Per-item relevance seals (mirrors seal_item in mystery/cases/package.py): Hobby Detective checks
## open exactly one item's verdict, never the truth.
const REL_SCHEME := "sha256-xor-item/1"
const REL_SALT := "project-mystery relevance v1"
const REL_VALUES := ["connected|web", "unrelated|outside", "uncertain|where_when", "uncertain|untraced"]


static func open_relevance(pkg: Dictionary, ref: String) -> String:
	## "<verdict>|<reason>" for one item, or "" if the package has no verdict for it.
	var rel = pkg.get("relevance")
	if typeof(rel) != TYPE_DICTIONARY or rel.get("scheme") != REL_SCHEME:
		return ""
	var items = rel.get("items")
	if typeof(items) != TYPE_DICTIONARY or not items.has(ref):
		return ""
	var cipher := Marshalls.base64_to_raw(String(items[ref]))
	var key := ("%s|%s|%s" % [REL_SALT, String(pkg.get("case_id", "")), ref]).sha256_buffer()
	var out := PackedByteArray()
	out.resize(cipher.size())
	for i in range(mini(cipher.size(), key.size())):
		out[i] = cipher[i] ^ key[i]
	return out.get_string_from_ascii().strip_edges()


static func validate(pkg) -> Array:
	## Every rule mirrors validate_package() in mystery/cases/package.py.
	var p := []
	if typeof(pkg) != TYPE_DICTIONARY:
		return ["package is not a JSON object"]
	if pkg.get("format") != FORMAT:
		return ["This is not a Project Mystery case file."]
	var version = pkg.get("format_version")
	if not _is_int(version) or not SUPPORTED_VERSIONS.has(int(version)):
		return ["This case uses format version %s; this build of the game reads version %s." % [str(version), str(SUPPORTED_VERSIONS)]]
	var case_id = _need(pkg, "case_id", "str", "package", p)
	for k in ["title", "town", "start_label", "season", "difficulty"]:
		_need(pkg.get("summary"), k, "str", "summary", p)
	for k in ["sim_version", "config_version", "profile"]:
		_need(pkg.get("generator"), k, "str", "generator", p)
	for k in ["seed", "days", "residents"]:
		_need(pkg.get("generator"), k, "int", "generator", p)
	var sealed = _need(pkg, "sealed_truth", "dict", "package", p)
	if sealed != null:
		if sealed.get("scheme") != SEAL_SCHEME:
			p.append("sealed_truth: unknown scheme")
		for k in ["data", "data_sha256", "plain_sha256"]:
			_need(sealed, k, "str", "sealed_truth", p)
		_need(sealed, "length", "int", "sealed_truth", p)
		if typeof(sealed.get("data")) == TYPE_STRING and String(sealed["data"]).sha256_text() != sealed.get("data_sha256"):
			p.append("sealed_truth: data checksum mismatch (corrupted or edited)")
	var rel = pkg.get("relevance")
	if rel != null:
		# optional: per-item sealed verdicts for Hobby Detective checks
		if typeof(rel) != TYPE_DICTIONARY or rel.get("scheme") != REL_SCHEME or typeof(rel.get("items")) != TYPE_DICTIONARY:
			p.append("relevance: unknown scheme or malformed")
		elif typeof(case_id) == TYPE_STRING:
			for ref in rel["items"]:
				if not REL_VALUES.has(open_relevance(pkg, String(ref))):
					p.append("relevance: item %s does not open" % ref)
					break
	var inv = _need(pkg, "investigation", "dict", "package", p)
	if inv == null:
		return p
	for x in spoiler_problems(inv):
		p.append("spoiler boundary: " + x)
	if inv.get("case_id") != case_id:
		p.append("investigation.case_id does not match the package case_id")
	for k in ["schema", "case_id", "town", "start_label", "player_role"]:
		_need(inv, k, "str", "investigation", p)
	_need(inv, "start_time", "int", "investigation", p)
	_need(inv, "hint_credits", "int", "investigation", p)
	var hook = _need(inv, "hook", "dict", "investigation", p)
	if hook != null:
		for k in ["title", "text", "kind", "place", "window_label", "discovered_by"]:
			_need(hook, k, "str", "hook", p)
		var w = _need(hook, "window", "list", "hook", p)
		if w != null and (w.size() != 2 or not _is_int(w[0]) or not _is_int(w[1])):
			p.append("hook: window must be two integer times")
		if typeof(hook) == TYPE_DICTIONARY and hook.has("recent_from") and not _is_int(hook["recent_from"]):
			p.append("hook: recent_from must be an integer time")
	var rids := {}
	var residents := _list(_need(inv, "residents", "list", "investigation", p))
	for i in range(residents.size()):
		var r = residents[i]
		for k in ["id", "name", "first", "occupation", "age_group", "household", "home", "condition"]:
			_need(r, k, "str", "residents[%d]" % i, p)
		if typeof(r) == TYPE_DICTIONARY and typeof(r.get("id")) == TYPE_STRING:
			rids[r["id"]] = true
	var pids := {}
	var places := _list(_need(inv, "places", "list", "investigation", p))
	for i in range(places.size()):
		var pl = places[i]
		var w := "places[%d]" % i
		for k in ["id", "name", "kind", "reply"]:
			_need(pl, k, "str", w, p)
		_need(pl, "allowed", "bool", w, p)
		for o in _list(_need(pl, "owners", "list", w, p)):
			if not rids.has(o):
				p.append("%s: unknown owner %s" % [w, str(o)])
		var traces := _list(_need(pl, "traces", "list", w, p))
		for j in range(traces.size()):
			_need(traces[j], "id", "str", "%s.traces[%d]" % [w, j], p)
			_need(traces[j], "description", "str", "%s.traces[%d]" % [w, j], p)
		if typeof(pl) == TYPE_DICTIONARY and typeof(pl.get("id")) == TYPE_STRING:
			pids[pl["id"]] = true
	if hook != null and not pids.has(hook.get("place")):
		p.append("hook: place is not a known place")
	for i in range(residents.size()):
		# optional (schema 0.2): where the resident can be found during the investigation
		var r = residents[i]
		if typeof(r) == TYPE_DICTIONARY and r.get("now_at") != null and not pids.has(r.get("now_at")):
			p.append("residents[%d]: now_at is not a known place" % i)
	var vehicles := _list(_need(inv, "vehicles", "list", "investigation", p))
	for i in range(vehicles.size()):
		var v = vehicles[i]
		var w := "vehicles[%d]" % i
		for k in ["id", "name", "kind", "household", "location", "reply"]:
			_need(v, k, "str", w, p)
		_need(v, "allowed", "bool", w, p)
		_need(v, "traces", "list", w, p)
		if typeof(v) == TYPE_DICTIONARY and not pids.has(v.get("location")):
			p.append("%s: parked at an unknown place" % w)
	var records := _dict(_need(inv, "records", "dict", "investigation", p))
	for key in records:
		var b = records[key]
		var w := "records.%s" % key
		for k in ["title", "place", "reply"]:
			_need(b, k, "str", w, p)
		_need(b, "allowed", "bool", w, p)
		var entries := _list(_need(b, "entries", "list", w, p))
		for j in range(entries.size()):
			_need(entries[j], "id", "str", "%s[%d]" % [w, j], p)
			_need(entries[j], "time", "int", "%s[%d]" % [w, j], p)
			_need(entries[j], "text", "str", "%s[%d]" % [w, j], p)
		if typeof(b) == TYPE_DICTIONARY and not pids.has(b.get("place")):
			p.append("%s: kept at an unknown place" % w)
	var valid_topics := {"other": true}
	for t in BASE_TOPICS:
		valid_topics[t] = true
	for r in rids:
		valid_topics["person:" + r] = true
	var keys := {}
	var testimony := _dict(_need(inv, "testimony", "dict", "investigation", p))
	for rid in testimony:
		var t = testimony[rid]
		var where := "testimony.%s" % rid
		if not rids.has(rid):
			p.append("%s: not a resident" % where)
		_need(t, "goodwill", "int", where, p)
		if typeof(t) == TYPE_DICTIONARY and not STYLES.has(t.get("style")):
			p.append("%s: style must be nervous or smooth" % where)
		for tp in _list(_need(t, "evasive_topics", "list", where, p)):
			if not valid_topics.has(tp):
				p.append("%s: unknown evasive topic %s" % [where, str(tp)])
		var items := _list(_need(t, "items", "list", where, p))
		for j in range(items.size()):
			var it = items[j]
			var w := "%s.items[%d]" % [where, j]
			var k = _need(it, "key", "str", w, p)
			if k != null and keys.has(k):
				p.append("%s: duplicate key %s" % [w, k])
			keys[k] = true
			_need(it, "text", "str", w, p)
			_need(it, "guarded", "bool", w, p)
			_need(it, "time", "int?", w, p)
			_need(it, "place", "str?", w, p)
			if typeof(it) == TYPE_DICTIONARY and not SOURCES.has(it.get("source")):
				p.append("%s: unknown source" % w)
			for tp in _list(_need(it, "topics", "list", w, p)):
				if not valid_topics.has(tp):
					p.append("%s: unknown topic %s" % [w, str(tp)])
			for a in _list(_need(it, "about", "list", w, p)):
				if not rids.has(a):
					p.append("%s: about unknown resident %s" % [w, str(a)])
			for f in _list(_need(it, "facts", "list", w, p)):
				if typeof(f) != TYPE_DICTIONARY or not rids.has(f.get("who")) or not pids.has(f.get("place")) \
						or not _is_int(f.get("from")) or not _is_int(f.get("to")) or float(f["from"]) > float(f["to"]):
					p.append("%s: malformed fact" % w)
			if typeof(it) == TYPE_DICTIONARY and it.has("group"):
				var g = it["group"]
				if typeof(g) != TYPE_DICTIONARY or not str(g.get("template", "")).contains("{names}") or not g.get("id"):
					p.append("%s: malformed group" % w)
			if typeof(it) == TYPE_DICTIONARY and it.has("era") and it["era"] != "earlier":
				p.append("%s: era must be 'earlier' when given" % w)
		_check_layers(items, where, p)
	var opts := _dict(_need(inv, "theory_options", "dict", "investigation", p))
	for kind in ["mechanisms", "motives"]:
		var list := _list(_need(opts, kind, "list", "theory_options", p))
		for j in range(list.size()):
			_need(list[j], "id", "str", "theory_options.%s[%d]" % [kind, j], p)
			_need(list[j], "label", "str", "theory_options.%s[%d]" % [kind, j], p)
	var hints := _list(_need(inv, "hints", "list", "investigation", p))
	for j in range(hints.size()):
		_need(hints[j], "tier", "int", "hints[%d]" % j, p)
		_need(hints[j], "cost", "int", "hints[%d]" % j, p)
		_need(hints[j], "text", "str", "hints[%d]" % j, p)
	return p


# --------------------------------------------------------------------------- seal
static func _keystream_block(case_id: String, counter: int) -> PackedByteArray:
	return ("%s|%s|%d" % [SEAL_SALT, case_id, counter]).sha256_buffer()


static func sha256_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


static func unseal(sealed: Dictionary, case_id: String) -> Dictionary:
	## Returns {"ok": bool, "truth": Dictionary or null, "error": String}. Only the reveal calls this.
	if sealed.get("scheme") != SEAL_SCHEME:
		return {"ok": false, "truth": null, "error": "unknown seal scheme"}
	var data: String = sealed.get("data", "")
	if data.sha256_text() != sealed.get("data_sha256"):
		return {"ok": false, "truth": null, "error": "the sealed truth is corrupted"}
	var cipher := Marshalls.base64_to_raw(data)
	var plain := PackedByteArray()
	plain.resize(cipher.size())
	var pos := 0
	var counter := 0
	while pos < cipher.size():
		var block := _keystream_block(case_id, counter)
		for i in range(block.size()):
			if pos >= cipher.size():
				break
			plain[pos] = cipher[pos] ^ block[i]
			pos += 1
		counter += 1
	if plain.size() != int(sealed.get("length", -1)) or sha256_hex(plain) != sealed.get("plain_sha256"):
		return {"ok": false, "truth": null, "error": "the sealed truth does not match its checksum"}
	var json := JSON.new()
	if json.parse(plain.get_string_from_ascii()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "truth": null, "error": "the sealed truth is not readable"}
	return {"ok": true, "truth": json.data, "error": ""}


static func _check_layers(items: Array, where: String, p: Array) -> void:
	## Optional (schema 0.3): a statement with "members" stands for those statements of the same person,
	## each of which names it back with "in".
	var by_key := {}
	for it in items:
		if typeof(it) == TYPE_DICTIONARY:
			by_key[it.get("key")] = it
	for k in by_key:
		var it: Dictionary = by_key[k]
		if it.has("members"):
			var ms = it["members"]
			var ok: bool = typeof(ms) == TYPE_ARRAY and not ms.is_empty()
			if ok:
				for m in ms:
					if not by_key.has(m) or by_key[m].get("in") != k:
						ok = false
			if not ok:
				p.append("%s.%s: members that do not name it back" % [where, k])
		if it.has("in"):
			var front = by_key.get(it["in"])
			if typeof(front) != TYPE_DICTIONARY or not front.get("members", []).has(k):
				p.append("%s.%s: filed behind a statement that does not list it" % [where, k])
