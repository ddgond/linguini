extends Node
## Exits 0 if the native extension loaded (used to smoke-test packaged builds):
##   ./Linguini.x86_64 --headless -- --tool=check_extension

## Positional command-line arguments, set by main.gd before the tool starts.
var args := PackedStringArray()


func _ready() -> void:
	if ClassDB.class_exists("MoonlightClient"):
		print("Linguini extension loaded (Godot %s)" % Engine.get_version_info().string)
		get_tree().quit(0)
	else:
		print("Linguini extension NOT loaded")
		get_tree().quit(1)
