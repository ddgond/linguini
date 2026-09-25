class_name TankDecor
extends Node3D
## All the decor in the tank, saved with the tank preset as a "decor" list:
##   {"type": "castle", "position": [x, y, z], "yaw": 30, "size": "M", "variant": 0}
## Positions are in tank space (origin at the inside bottom of the tank).
##
## Where a piece may go depends on its anchor: gravel pieces sit on the gravel,
## float pieces go anywhere in the water, surface pieces float on the water
## line, and rim pieces (the filter) hang on the back or side rims.

## The water volume, tank space.
var water := AABB(Vector3(-0.6, 0.03, -0.25), Vector3(1.2, 0.53, 0.5))

var pieces: Array[DecorPiece] = []


func load_data(entries: Array) -> void:
	clear()
	for e: Dictionary in entries:
		if DecorCatalog.item(String(e.get("type", ""))).is_empty():
			push_warning("TankDecor: unknown decor type '%s'" % e.get("type"))
			continue
		var p: Array = e.get("position", [0, 0, 0])
		add_piece(String(e.type), Vector3(p[0], p[1], p[2]), float(e.get("yaw", 0.0)),
				String(e.get("size", "M")), int(e.get("variant", 0)))


func to_data() -> Array:
	return pieces.map(func(p: DecorPiece) -> Dictionary: return p.to_dict())


func clear() -> void:
	for p in pieces:
		remove_child(p)
		p.queue_free()
	pieces.clear()


func add_piece(type: String, pos: Vector3, yaw := 0.0, size := "M", variant := 0) -> DecorPiece:
	var piece := DecorPiece.new(type, variant, size, yaw)
	piece.water_level = water.end.y
	piece.position = place(piece, pos)
	add_child(piece)
	pieces.append(piece)
	if piece.anchor() == "rim":
		piece.set_yaw(_rim_yaw(piece.position))
	return piece


func remove_piece(piece: DecorPiece) -> void:
	pieces.erase(piece)
	remove_child(piece)
	piece.queue_free()


func move_piece(piece: DecorPiece, pos: Vector3) -> void:
	piece.position = place(piece, pos)
	if piece.ball:
		piece.ball.place(piece.position)
	if piece.anchor() == "rim":
		piece.set_yaw(_rim_yaw(piece.position))


## Where `piece` ends up if asked to go to `pos`, following its anchor.
func place(piece: DecorPiece, pos: Vector3) -> Vector3:
	var margin := 0.03
	var x := clampf(pos.x, water.position.x + margin, water.end.x - margin)
	var z := clampf(pos.z, water.position.z + margin, water.end.z - margin)
	match piece.anchor():
		"gravel":
			return Vector3(x, water.position.y, z)
		"surface":
			return Vector3(x, water.end.y, z)
		"float":
			return Vector3(x, clampf(pos.y, water.position.y + 0.04, water.end.y - 0.04), z)
		"rim":
			return _rim_point(pos)
	return pos


## The nearest point on the back or side rims (not the front, which faces the
## room camera). Rim pieces sit on the inside top edge of the glass.
func _rim_point(pos: Vector3) -> Vector3:
	var top := 0.6
	var inner := water.grow(0.0)
	var candidates := [
		Vector3(clampf(pos.x, inner.position.x + 0.08, inner.end.x - 0.08), top, inner.position.z),  # back
		Vector3(inner.position.x, top, clampf(pos.z, inner.position.z + 0.08, inner.end.z - 0.12)),  # left
		Vector3(inner.end.x, top, clampf(pos.z, inner.position.z + 0.08, inner.end.z - 0.12)),       # right
	]
	var flat := Vector3(pos.x, top, pos.z)
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(flat) < b.distance_to(flat))
	return candidates[0]


## Faces a rim piece into the tank. Its body hangs at -Z in its own space (the
## model's Blender +Y) and its spillway pours toward +Z, so on the back rim it
## needs no turn; on a side rim it turns so the body hangs outside that glass.
func _rim_yaw(pos: Vector3) -> float:
	if is_equal_approx(pos.x, water.position.x):
		return 90.0
	if is_equal_approx(pos.x, water.end.x):
		return -90.0
	return 0.0
