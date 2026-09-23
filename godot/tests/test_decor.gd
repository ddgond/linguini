extends "res://tests/test_case.gd"
## Tank decor: the catalogue, placement by anchor, solid vs soft pieces,
## saving and loading with presets, and the editor.


func _main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add(main)
	await tree.process_frame
	return main


func test_catalogue_models_exist() -> void:
	for id in DecorCatalog.ids():
		var item := DecorCatalog.item(id)
		check(ResourceLoader.exists("res://art/decor/%s.glb" % id), "%s has a model" % id)
		check(item.get("variants", []).size() >= 2, "%s has colour variants" % id)
		check(item.kind in ["solid", "soft"] and item.anchor in ["gravel", "float", "surface", "rim"], "%s has a valid kind and anchor" % id)


func test_anchors_place_pieces() -> void:
	var main := await _main()
	var decor: TankDecor = main.decor
	var rock := decor.add_piece("rock_round", Vector3(0.1, 0.4, 0.0))
	check(is_equal_approx(rock.position.y, decor.water.position.y), "gravel pieces sit on the gravel (%s)" % rock.position)
	var pad := decor.add_piece("lily_pad", Vector3(0.1, 0.1, 0.0))
	check(is_equal_approx(pad.position.y, decor.water.end.y), "lily pads float on the surface (%s)" % pad.position)
	var moss := decor.add_piece("moss_ball", Vector3(0.1, 0.3, 0.0))
	check(is_equal_approx(moss.position.y, 0.3), "moss balls stay where they're put (%s)" % moss.position)
	var filter := decor.add_piece("filter", Vector3(0.1, 0.0, 0.2))
	check(is_equal_approx(filter.position.z, decor.water.position.z) or is_equal_approx(absf(filter.position.x), decor.water.end.x),
		"the filter snaps to the back or a side rim, never the front (%s)" % filter.position)
	decor.move_piece(filter, Vector3(0.62, 0.0, 0.0))
	check(is_equal_approx(filter.position.x, decor.water.end.x) and is_equal_approx(filter.yaw, 270.0),
		"on the right rim it turns to hang outside that glass (%s, yaw %s)" % [filter.position, filter.yaw])
	decor.move_piece(rock, Vector3(5, 5, 5))
	check(decor.water.grow(0.001).has_point(rock.position), "pieces can't leave the tank (%s)" % rock.position)
	main.queue_free()


func test_solid_and_soft() -> void:
	var main := await _main()
	var decor: TankDecor = main.decor
	decor.clear()
	var rock := decor.add_piece("rock_round", Vector3(0.0, 0.0, 0.1), 0, "L")
	var grass := decor.add_piece("plant_grass", Vector3(-0.3, 0.0, 0.1), 0, "L")
	# New shapes reach the physics server a step or two later.
	for i in 3:
		await tree.physics_frame
	var space := main.get_world_3d().direct_space_state
	# Trimesh shapes are surfaces, so probe with a ray down onto the rock.
	var down := PhysicsRayQueryParameters3D.create(main.room.tank.to_global(Vector3(0.0, 0.3, 0.1)), main.room.tank.to_global(Vector3(0.0, 0.035, 0.1)), 1)
	var hit: Dictionary = space.intersect_ray(down)
	check(not hit.is_empty() and hit.collider.get_parent() == rock, "a rock is solid to the fish (hit %s)" % [hit.get("collider")])
	var ray := PhysicsRayQueryParameters3D.create(main.room.tank.to_global(Vector3(-0.3, 0.1, 0.24)), main.room.tank.to_global(Vector3(-0.3, 0.1, -0.2)), 1)
	var hits := space.intersect_ray(ray)
	check(hits.is_empty() or not (hits.collider.get_parent() is DecorPiece), "the fish swims through grass")
	ray.collision_mask = 2
	var pick: Dictionary = space.intersect_ray(ray)
	check(not pick.is_empty(), "but the editor can still click it")
	main.queue_free()


func test_round_trip_with_preset() -> void:
	var main := await _main()
	var editor: TankEditor = main.editor
	var decor: TankDecor = main.decor
	decor.clear()
	decor.add_piece("castle", Vector3(0.3, 0.0, 0.0), 45.0, "L", 2)
	decor.add_piece("moss_ball", Vector3(-0.2, 0.3, 0.05), 0.0, "S", 1)
	var data := editor.layout_data("Round trip")
	var copy: Dictionary = JSON.parse_string(JSON.stringify(data))
	decor.clear()
	decor.load_data(copy.decor)
	check(decor.pieces.size() == 2, "both pieces come back")
	var castle := decor.pieces[0]
	check(castle.type == "castle" and castle.size == "L" and castle.variant == 2 and is_equal_approx(castle.yaw, 45.0),
		"with their type, size, colour and rotation (%s)" % castle.to_dict())
	main.queue_free()


func test_editor_decor() -> void:
	var main := await _main()
	main.open_editor()
	var editor: TankEditor = main.editor
	var decor: TankDecor = main.decor
	var before := decor.pieces.size()
	editor._decor_choice.select(DecorCatalog.ids().find("chest"))
	editor._on_add_decor()
	check(decor.pieces.size() == before + 1 and editor.selected_decor != null and editor.selected_decor.type == "chest",
		"+ Decor adds and selects the chosen piece")
	check(editor.dirty, "and marks the layout unsaved")
	editor._on_duplicate()
	check(decor.pieces.size() == before + 2, "Duplicate copies decor too")
	editor._on_delete_selected()
	check(decor.pieces.size() == before + 1 and editor.selected_decor == null, "Delete removes it")
	main.queue_free()
