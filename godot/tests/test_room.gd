extends "res://tests/test_case.gd"
## The bedroom: the room model lands around the tank, is lit by its baked
## lightmaps, and the moods switch its lighting, the street outside and rain.


func _main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add(main)
	await tree.process_frame
	return main


func _room_surfaces(main: Node3D) -> Array:
	var out := []
	var model: Node3D = main.room.room_model
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "WindowGlass":
			continue
		for i in mi.mesh.get_surface_count():
			out.append([mi, i])
	return out


func test_room_lands_around_the_tank() -> void:
	var main := await _main()
	var layout := RoomBuilder.load_layout()
	check(not layout.is_empty(), "layout.json loads")
	var model: Node3D = main.room.room_model
	var tank_spot := model.global_position + Vector3(layout.tank_origin[0], layout.tank_origin[1], layout.tank_origin[2])
	check(tank_spot.is_equal_approx(RoomBuilder.TANK_ORIGIN), "the room's tank spot is the tank (%s)" % tank_spot)
	var screen: Node3D = main.room.screen
	var expected := model.global_position + Vector3(layout.screen_center[0], layout.screen_center[1], layout.screen_center[2])
	check(screen.global_position.distance_to(expected) < 0.01, "the picture sits on the room's monitor (%s vs %s)" % [screen.global_position, expected])
	check(main.room.speakers.size() == 2, "two speakers")
	var cam: Camera3D = main.room.room_camera
	var to_tank := (RoomBuilder.TANK_ORIGIN - cam.global_position).normalized()
	check(-cam.global_basis.z.dot(to_tank) > 0.95, "the room camera looks at the tank")
	main.queue_free()


func test_room_is_lightmapped() -> void:
	var main := await _main()
	var surfaces := _room_surfaces(main)
	check(surfaces.size() > 10, "the room has its materials (%d surfaces)" % surfaces.size())
	var wrong := []
	var no_uv2 := []
	for s: Array in surfaces:
		var mi: MeshInstance3D = s[0]
		var mat := mi.get_surface_override_material(s[1]) as ShaderMaterial
		if mat == null or mat.shader != RoomBuilder.ROOM_SHADER:
			wrong.append(mi.mesh.surface_get_material(s[1]).resource_name)
		if mi.mesh.surface_get_arrays(s[1])[Mesh.ARRAY_TEX_UV2] == null:
			no_uv2.append(mi.mesh.surface_get_material(s[1]).resource_name)
		check(mi.layers == RoomBuilder.ROOM_LAYER, "%s is on the room layer" % mi.name)
	check(wrong.is_empty(), "every room surface uses the room shader (not: %s)" % [wrong])
	check(no_uv2.is_empty(), "every room surface has lightmap UVs (not: %s)" % [no_uv2])

	# Pictures and lettering keep their colours: dressing that missed a vertex
	# colour fill would turn black when joined.
	for s: Array in surfaces:
		var mi: MeshInstance3D = s[0]
		var name: String = mi.mesh.surface_get_material(s[1]).resource_name
		if name.begins_with("Poster") or name == "GlowChat":
			var colors: PackedColorArray = mi.mesh.surface_get_arrays(s[1])[Mesh.ARRAY_COLOR]
			var dark := 0
			for c in colors:
				if c.v < 0.5:
					dark += 1
			check(dark == 0, "%s isn't darkened by vertex colour (%d dark vertices)" % [name, dark])

	for light: Light3D in main.find_children("*", "Light3D", true, false):
		if light.name in ["WindowLight", "Lamp", "FairyLights", "RGBAccent"] or light.name.begins_with("Lamp"):
			check(light.light_cull_mask & RoomBuilder.ROOM_LAYER == 0, "%s leaves the baked room alone" % light.name)
	main.queue_free()


func test_moods_switch_the_room() -> void:
	var original: String = Mood.current
	var stored: String = Settings.get_value("room", "mood", "night")
	var main := await _main()
	var moods: RoomMoods = main.room.moods
	var wall: ShaderMaterial = moods.materials.get("Wall")
	check(wall != null, "the walls' material is known")

	Mood.set_mood("night", false)
	var night_map: Texture2D = wall.get_shader_parameter("lightmap")
	check(float(moods.glass_material.get_shader_parameter("rain")) == 0.0, "no rain at night")

	Mood.set_mood("rainy", false)
	check(wall.get_shader_parameter("lightmap") != night_map, "rain has its own lightmap")
	check(float(moods.glass_material.get_shader_parameter("rain")) > 0.5, "rain on the glass when it's rainy")
	check(moods.street.mood == "rainy", "the street outside turns rainy too")

	Mood.set_mood("golden", false)
	check(moods.lamps.all(func(l: Light3D) -> bool: return not l.visible), "lamps off at golden hour")
	check(moods.window_light.light_energy > 1.0, "the sun comes through the window")
	check(Settings.get_value("room", "mood", "night") == stored, "a mood set without remembering isn't saved")

	Mood.set_mood(original, false)
	main.queue_free()


func test_mood_picker_on_the_monitor() -> void:
	var original: String = Mood.current
	var main := await _main()
	var pickers: Array = main.menu.find_children("MoodPicker", "OptionButton", true, false)
	check(pickers.size() == 1, "the home page has a mood picker")
	if pickers.size() == 1:
		var picker: OptionButton = pickers[0]
		check(picker.item_count == Mood.NAMES.size(), "one entry per mood")
		picker.select(Mood.NAMES.find("golden"))
		picker.item_selected.emit(picker.selected)
		check(Mood.current == "golden", "picking a mood applies it")
		check(Settings.get_value("room", "mood", "") == "golden", "and it's remembered")
	Mood.set_mood(original)
	main.queue_free()
