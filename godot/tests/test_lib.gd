## A tiny assertion library. A test that aborts on a script error never reaches end() and is
## counted as a failure, so a crash can never pass silently.
extends RefCounted

var suite := ""
var current := ""
var open := false
var passed := 0
var failed := 0
var tests := 0
var failures := PackedStringArray()


func begin(name: String) -> void:
	if open:
		_record_failure("aborted before finishing (script error?)")
	current = "%s :: %s" % [suite, name]
	open = true
	tests += 1


func end() -> void:
	open = false


func _record_failure(msg: String) -> void:
	failed += 1
	failures.append("%s: %s" % [current, msg])
	printerr("FAIL  %s: %s" % [current, msg])


func check(cond: bool, msg := "") -> bool:
	if cond:
		passed += 1
	else:
		_record_failure(msg)
	return cond


func eq(actual, expected, msg := "") -> bool:
	var d := diff(actual, expected, "")
	return check(d == "", msg + ("" if d == "" else " | " + d))


func ok() -> bool:
	if open:
		_record_failure("aborted before finishing (script error?)")
		open = false
	return failed == 0 and tests > 0


func summary() -> String:
	var good := ok()
	var lines := PackedStringArray()
	lines.append("%d tests, %d checks passed, %d failed" % [tests, passed, failed])
	for f in failures:
		lines.append("  - " + f)
	lines.append("ALL GODOT TESTS PASSED" if good else "GODOT TESTS FAILED")
	return "\n".join(lines)


static func _num(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func short(v) -> String:
	var s := str(v)
	return s if s.length() <= 160 else s.left(157) + "..."


static func diff(a, b, path: String) -> String:
	## "" when equal (ints and floats compare by value, like JSON), else the first difference.
	if _num(a) and _num(b):
		return "" if float(a) == float(b) else "%s: %s != %s" % [path, short(a), short(b)]
	if typeof(a) != typeof(b):
		return "%s: %s (%s) vs expected %s (%s)" % [path, short(a), type_string(typeof(a)), short(b), type_string(typeof(b))]
	if typeof(a) == TYPE_DICTIONARY:
		for k in b:
			if not a.has(k):
				return "%s.%s: missing" % [path, k]
		for k in a:
			if not b.has(k):
				return "%s.%s: unexpected" % [path, k]
			var d := diff(a[k], b[k], "%s.%s" % [path, k])
			if d != "":
				return d
		return ""
	if typeof(a) == TYPE_ARRAY:
		if a.size() != b.size():
			return "%s: length %d vs expected %d" % [path, a.size(), b.size()]
		for i in range(a.size()):
			var d := diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s != expected %s" % [path, short(a), short(b)]
