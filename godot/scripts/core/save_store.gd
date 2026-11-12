## Investigation saves and settings under user:// (on Windows: %APPDATA%\ProjectMystery).
## A save is the investigation state only - notebook, conversations, credits, theory, score -
## never any part of the sealed truth.
extends RefCounted

## The newest saved-state layout this build understands (Investigation.STATE_VERSION).
const MAX_STATE_VERSION := 2
const DEFAULT_SETTINGS := {"text_size": 1, "high_contrast": false, "fullscreen": false, "mode": "normal"}

var root: String


func _init(base := "user://") -> void:
	root = base if base.ends_with("/") else base + "/"
	DirAccess.make_dir_recursive_absolute(root + "saves")


static func _safe(case_id: String) -> String:
	var out := ""
	for ch in case_id:
		out += ch if (ch.is_valid_identifier() or ch.is_valid_int() or ch == "-") else "_"
	return out


func save_path(case_id: String) -> String:
	return root + "saves/" + _safe(case_id) + ".json"


func _write(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) == OK:
		return true
	# rename refused (some file systems): fall back to a direct write
	var g := FileAccess.open(path, FileAccess.WRITE)
	if g == null:
		return false
	g.store_string(text)
	g.close()
	DirAccess.remove_absolute(tmp)
	return true


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return json.data


func save(state: Dictionary) -> bool:
	state["saved_at"] = Time.get_unix_time_from_system()
	return _write(save_path(state["case_id"]), JSON.stringify(state, "\t"))


func load_state(case_id: String):
	## The saved state for a case, or null.
	var d = _read_json(save_path(case_id))
	if typeof(d) != TYPE_DICTIONARY or d.get("case_id") != case_id:
		return null
	if int(d.get("state_version", 1)) > MAX_STATE_VERSION:
		return null
	return d


func has_save(case_id: String) -> bool:
	return FileAccess.file_exists(save_path(case_id))


func delete_save(case_id: String) -> void:
	if has_save(case_id):
		DirAccess.remove_absolute(save_path(case_id))


func list_saves() -> Array:
	## [{case_id, saved_at, entries, concluded, revealed, score}], most recent first.
	var out := []
	var dir := DirAccess.open(root + "saves")
	if dir == null:
		return out
	for name in dir.get_files():
		if not name.ends_with(".json"):
			continue
		var d = _read_json(root + "saves/" + name)
		if typeof(d) != TYPE_DICTIONARY or typeof(d.get("case_id")) != TYPE_STRING:
			continue
		var score = null
		if typeof(d.get("score")) == TYPE_DICTIONARY:
			score = int(d["score"].get("total", 0))
		out.append({"case_id": d["case_id"], "saved_at": float(d.get("saved_at", 0.0)),
				"entries": d.get("entries", []).size(), "concluded": bool(d.get("concluded", false)),
				"revealed": bool(d.get("revealed", false)), "score": score})
	out.sort_custom(_newer_first)
	return out


func _newer_first(a: Dictionary, b: Dictionary) -> bool:
	if a["saved_at"] != b["saved_at"]:
		return a["saved_at"] > b["saved_at"]
	return String(a["case_id"]) < String(b["case_id"])


func load_settings() -> Dictionary:
	var out := DEFAULT_SETTINGS.duplicate()
	var d = _read_json(root + "settings.json")
	if typeof(d) == TYPE_DICTIONARY:
		for k in DEFAULT_SETTINGS:
			if d.has(k):
				out[k] = d[k]
	out["text_size"] = clampi(int(out["text_size"]), 0, 3)
	out["high_contrast"] = bool(out["high_contrast"])
	out["fullscreen"] = bool(out["fullscreen"])
	if not ["normal", "hobby"].has(String(out["mode"])):
		out["mode"] = "normal"
	return out


func save_settings(settings: Dictionary) -> void:
	_write(root + "settings.json", JSON.stringify(settings, "\t"))


func reset_all() -> void:
	for s in list_saves():
		delete_save(s["case_id"])
