class_name LayoutPresets
extends RefCounted
## Named card layouts. Built-in presets ship in res://data/layouts and are
## read-only; the player's own are saved as JSON in user://layouts.

const BUILTIN_DIR := "res://data/layouts"
const USER_DIR := "user://layouts"
const DEFAULT := "Default"


## [{name, path, builtin}], built-ins first, each group sorted by name.
static func list() -> Array[Dictionary]:
	var builtin := _scan(BUILTIN_DIR, true)
	var user := _scan(USER_DIR, false)
	var names := {}
	for p in builtin:
		names[p.name] = true
	# A user preset can't shadow a built-in one.
	user = user.filter(func(p: Dictionary) -> bool: return not names.has(p.name))
	return builtin + user


static func find(preset_name: String) -> Dictionary:
	for p in list():
		if p.name == preset_name:
			return p
	return {}


static func is_builtin(preset_name: String) -> bool:
	return find(preset_name).get("builtin", false)


static func load_data(preset_name: String) -> Dictionary:
	var p := find(preset_name)
	if p.is_empty():
		return {}
	return read(p.path)


static func read(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if typeof(data) == TYPE_DICTIONARY and data.has("cards") else {}


## Saves `data` as the user preset `preset_name`. Returns "" or an error message.
static func save(preset_name: String, data: Dictionary) -> String:
	preset_name = preset_name.strip_edges()
	if preset_name == "":
		return "Give the preset a name"
	if is_builtin(preset_name):
		return "'%s' is a built-in preset; save under another name" % preset_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_DIR))
	var out := data.duplicate(true)
	out.name = preset_name
	var existing := find(preset_name)
	var path: String = existing.path if not existing.is_empty() else _free_path(preset_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Couldn't write %s" % path
	file.store_string(JSON.stringify(out, "\t", false))
	return ""


static func delete(preset_name: String) -> String:
	var p := find(preset_name)
	if p.is_empty():
		return "No preset named '%s'" % preset_name
	if p.builtin:
		return "Built-in presets can't be deleted"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p.path))
	return ""


static func _scan(dir_path: String, builtin: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var path := dir_path.path_join(file)
		var data := read(path)
		if data.is_empty():
			continue
		out.append({"name": String(data.get("name", file.get_basename())), "path": path, "builtin": builtin})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	return out


static func _free_path(preset_name: String) -> String:
	var slug := preset_name.to_lower().validate_filename().replace(" ", "-")
	if slug == "":
		slug = "layout"
	var path := USER_DIR.path_join(slug + ".json")
	var n := 2
	while FileAccess.file_exists(path):
		path = USER_DIR.path_join("%s-%d.json" % [slug, n])
		n += 1
	return path
