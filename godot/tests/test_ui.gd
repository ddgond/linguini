extends "res://tests/test_case.gd"
## The look of things: button glyph sets, the card slab, the monitor's idle
## desktop and tally lights (there's no HUD), the editor's decor palette and
## the tank cam's keypoints.


func _main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add(main)
	await tree.process_frame
	return main


func test_glyph_sets() -> void:
	var original: String = Glyphs.setting
	check(Glyphs.detect("Sony Interactive Entertainment DualSense Wireless Controller") == "playstation", "a DualSense shows PlayStation glyphs")
	check(Glyphs.detect("Nintendo Switch Pro Controller") == "nintendo", "a Switch Pro shows Nintendo glyphs")
	check(Glyphs.detect("Xbox Series Controller") == "xbox" and Glyphs.detect("Some Generic Pad") == "xbox", "anything else shows Xbox")
	check(Glyphs.label("A", "playstation") == "✕" and Glyphs.label("LB", "playstation") == "L1", "PlayStation names: cross, L1")
	check(Glyphs.label("A", "nintendo") == "B" and Glyphs.label("Y", "nintendo") == "X" and Glyphs.label("RT", "nintendo") == "ZR",
		"Nintendo swaps the face letters by position")

	var changes := []
	var on_change := func(s: String) -> void: changes.append(s)
	Glyphs.changed.connect(on_change)
	Glyphs.set_setting("playstation")
	check(Glyphs.current == "playstation" and CardSystem.short_name("B") == "○", "picking a set renames inputs everywhere (%s)" % CardSystem.short_name("B"))
	check(changes == ["playstation"], "and says so (%s)" % [changes])
	check(Settings.get_value("controls", "glyphs", "") == "playstation", "the choice is remembered")
	Glyphs.changed.disconnect(on_change)
	Glyphs.set_setting(original)


func test_card_slab_faces_the_glass() -> void:
	var mesh := FlashCard.card_mesh(Vector2(0.11, 0.08), 0.007, 0.003)
	check(mesh.get_surface_count() == 2, "a printed front and a plain back")
	var front: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = front[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = front[Mesh.ARRAY_TEX_UV]
	check(Array(verts).all(func(v: Vector3) -> bool: return v.z > 0.0), "the front is on the +Z side, toward the glass")
	check(Array(uvs).all(func(u: Vector2) -> bool: return u.x >= -0.001 and u.x <= 1.001 and u.y >= -0.001 and u.y <= 1.001), "its UVs span the face")
	# Godot's front faces wind clockwise as seen from the front.
	var a := verts[0]
	var b := verts[1]
	var c := verts[2]
	check((b - a).cross(c - a).z < 0.0, "front triangles wind clockwise seen from +Z")


func test_no_hud_but_the_room_says_when_live() -> void:
	var main := await _main()
	check(main.find_children("*", "CanvasLayer", true, false).filter(func(n: Node) -> bool: return n.get_script() != null and n.get_script().get_global_name() == "Hud").is_empty(),
		"there's no HUD overlay")
	main.set_mode(main.Mode.SWIM)
	await tree.process_frame
	await tree.process_frame
	check(main.menu._idle, "swimming with no stream, the monitor idles on its desktop")
	var moods: RoomMoods = main.room.moods
	check(not moods.live and not moods.webcam_tally.visible, "tally lights are off when not streaming")
	moods.live = true
	check(moods.webcam_tally.visible and float(moods.materials.GlowTally.get_shader_parameter("emission_energy")) > 0.0, "and on when live")
	moods.live = false
	main.queue_free()


func test_editor_decor_palette() -> void:
	var main := await _main()
	main.open_editor()
	await tree.process_frame
	var editor: TankEditor = main.editor
	for id: String in DecorCatalog.ids():
		check(editor._decor_grid.has_node("Add_" + id), "the palette has %s" % id)
	var before: int = main.decor.to_data().size()
	(editor._decor_grid.get_node("Add_moss_ball") as Button).pressed.emit()
	var after: int = main.decor.to_data().size()
	check(after == before + 1, "a tile adds its piece (%d -> %d)" % [before, after])
	main.queue_free()


func test_tank_cam_keypoints() -> void:
	var main := await _main()
	main.set_tracking(true, TrackingCam.Style.EARNEST)
	main.fish.player_control = false
	main.fish.position = Vector3(0.0, 0.3, 0.12)
	for i in 4:
		await tree.process_frame
	var cam: TrackingCam = main.tracking
	check(cam.detected, "the fish is detected")
	check(cam.keypoints.size() == TrackingCam.KEYPOINTS.size(), "every keypoint is placed (%d)" % cam.keypoints.size())
	var inside := 0
	for p: Vector2 in cam.keypoints.values():
		if cam.box.grow(12.0).has_point(p):
			inside += 1
	check(inside == cam.keypoints.size(), "keypoints sit on the fish (%d of %d in its box)" % [inside, cam.keypoints.size()])
	main.set_tracking(false, TrackingCam.Style.EARNEST)
	main.queue_free()
