class_name LayoutPresets
extends RefCounted
## Named card layouts. Built-in presets ship in res://data/layouts and are
## read-only; the player's own are saved as JSON in user://layouts.

const BUILTIN_DIR := "res://data/layouts"
const USER_DIR := "user://layouts"
const DEFAULT := "Default"

## Random Grid (a preset with "generate": "random_grid"): columns and rows of
## cards over the back wall, each one of these inputs.
const GRID_COLUMNS := 9
const GRID_ROWS := 5
const GRID_INPUTS := ["A", "B", "X", "Y", "LB", "RB", "L3", "R3", "LT", "RT"]


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


## A preset's data. One with "generate" gets its cards made now (Random Grid:
## a fresh shuffle each time it's loaded).
static func read(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	if data.get("generate", "") == "random_grid":
		data.erase("generate")
		data.cards = random_grid()
	return data if data.has("cards") else {}


## Cards tiling the back wall, GRID_COLUMNS by GRID_ROWS, from the gravel to
## the water line and glass to glass. The inputs come from a shuffled bag
## holding each of GRID_INPUTS about as often, so all of them turn up.
static func random_grid(rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
	var half := CardSystem.CARD_SIZE * 0.5
	# Tank space: the inside spans x -0.6..0.6 and the water y 0.03..0.56.
	var x0 := -0.6 + half.x
	var x1 := 0.6 - half.x
	var y0 := 0.03 + half.y + 0.01
	var y1 := 0.56 - half.y - 0.005
	var bag: Array = []
	while bag.size() < GRID_COLUMNS * GRID_ROWS:
		bag.append_array(GRID_INPUTS)
	bag.resize(GRID_COLUMNS * GRID_ROWS)
	# Fisher-Yates with our generator, so a seeded one repeats (tests).
	for i in range(bag.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = bag[i]
		bag[i] = bag[j]
		bag[j] = t
	var cards := []
	for row in GRID_ROWS:
		for col in GRID_COLUMNS:
			var x := lerpf(x0, x1, float(col) / (GRID_COLUMNS - 1))
			var y := lerpf(y1, y0, float(row) / (GRID_ROWS - 1))
			cards.append({"inputs": [bag[row * GRID_COLUMNS + col]], "position": [snappedf(x, 0.001), snappedf(y, 0.001), -0.225]})
	return cards


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
