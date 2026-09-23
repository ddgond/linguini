extends Node
## Writes the Godot engine's licence and its third-party notices to a file:
##   godot --headless --path godot -- --tool=write_licenses OUT.txt

## Positional command-line arguments, set by main.gd before the tool starts.
var args := PackedStringArray()


func _ready() -> void:
	var path := args[0]
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string("Godot Engine\n\n" + Engine.get_license_text() + "\n\n")
	for part: Dictionary in Engine.get_copyright_info():
		out.store_string("%s\n" % part.name)
		for piece: Dictionary in part.parts:
			out.store_string("  Files: %s\n  Copyright: %s\n  License: %s\n" % [
				", ".join(piece.files), "\n             ".join(piece.copyright), piece.license])
		out.store_string("\n")
	var licenses := Engine.get_license_info()
	for name in licenses:
		out.store_string("License: %s\n\n%s\n\n" % [name, licenses[name]])
	get_tree().quit()
