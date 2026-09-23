class_name DecorCatalog
extends RefCounted
## The tank decor catalogue, read from res://data/decor.json (shared with the
## art pipeline, which uses it to colour its preview renders).

const PATH := "res://data/decor.json"
const SIZE_NAMES := ["S", "M", "L"]

static var _data: Dictionary


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data


static func ids() -> Array:
	return data().items.keys()


static func item(id: String) -> Dictionary:
	return data().items.get(id, {})


static func scene(id: String) -> PackedScene:
	return load("res://art/decor/%s.glb" % id)


static func size_scale(size: String) -> float:
	return data().sizes.get(size, 1.0)


static func variant(id: String, index: int) -> Dictionary:
	var variants: Array = item(id).get("variants", [{}])
	return variants[clampi(index, 0, variants.size() - 1)]
