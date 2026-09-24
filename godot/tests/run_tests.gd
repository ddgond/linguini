extends SceneTree
## Headless test runner:
##   godot --headless --path godot -s res://tests/run_tests.gd [-- --only=NAME]
## After adding a class_name script, run `godot --headless --path godot --import`
## once so the new class is registered.

const SUITES := [
	"res://tests/test_fish.gd",
	"res://tests/test_cards.gd",
	"res://tests/test_extension.gd",
	"res://tests/test_scene.gd",
	"res://tests/test_editor.gd",
	"res://tests/test_tracking.gd",
	"res://tests/test_audio.gd",
	"res://tests/test_decor.gd",
	"res://tests/test_art.gd",
	"res://tests/test_room.gd",
	"res://tests/test_street.gd",
	"res://tests/test_ui.gd",
	"res://tests/test_sound.gd",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var passed := 0
	var failed := 0
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			print("  FAIL %s: the suite doesn't compile (see errors above)" % path.get_file())
			continue
		var suite: RefCounted = script.new()
		suite.tree = self
		for method in suite.get_method_list():
			var name: String = method.name
			if not name.begins_with("test_") or (only != "" and not name.contains(only)):
				continue
			suite.failures.clear()
			await suite.call(name)
			if suite.failures.is_empty():
				passed += 1
				print("  ok   %s.%s" % [path.get_file().get_basename(), name])
			else:
				failed += 1
				print("  FAIL %s.%s" % [path.get_file().get_basename(), name])
				for f in suite.failures:
					print("         - " + f)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
