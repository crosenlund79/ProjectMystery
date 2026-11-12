## Headless test runner:
##   godot --headless --path godot -s res://tests/run_tests.gd
## Prints "ALL GODOT TESTS PASSED" and exits 0 only if every check passed and no test aborted.
extends SceneTree

const TestLib = preload("res://tests/test_lib.gd")
const SUITES := [
	"res://tests/test_case_format.gd",
	"res://tests/test_rules.gd",
	"res://tests/test_saves.gd",
	"res://tests/test_parity.gd",
	"res://tests/test_town.gd",
	"res://tests/test_evidence.gd",
	"res://tests/test_e2e.gd",
]


func _initialize() -> void:
	create_timer(900.0).timeout.connect(_timeout)
	_run()


func _timeout() -> void:
	printerr("TIMEOUT: the Godot tests did not finish")
	quit(2)


func _run() -> void:
	var t = TestLib.new()
	for path in SUITES:
		t.suite = path.get_file().get_basename()
		print("== %s" % t.suite)
		var script = load(path)
		if script == null or not script.can_instantiate():
			t.begin("load")
			t.check(false, "could not load %s (parse error?)" % path)
			t.end()
			continue
		await script.new().run(t, self)
	print(t.summary())
	quit(0 if t.ok() else 1)
