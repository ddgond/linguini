extends "res://tests/test_case.gd"
## The street outside the window: its own layer and lights, a shader for
## every material, moods that change it, signals that take turns and cars
## that stop at red.


func _main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add(main)
	await tree.process_frame
	return main


func test_street_sits_outside_on_its_own_layer() -> void:
	var main := await _main()
	var street: Street = main.room.street
	check(street != null, "there's a street")
	check(street.position.is_equal_approx(main.room.room_model.position), "placed like the room model")
	var meshes: Array = street.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() > 5, "the street has its meshes (%d)" % meshes.size())
	for mi: MeshInstance3D in meshes:
		check(mi.layers == Street.LAYER, "%s is on the street's layer" % mi.name)
	for light: Light3D in street.find_children("*", "Light3D", true, false):
		check(light.light_cull_mask == Street.LAYER, "%s lights only the street" % light.name)
	# Nothing of the room lights the street (it has its own ambient and sun).
	for light: Light3D in main.room.moods.lamps + [main.room.moods.window_light]:
		check(light.light_cull_mask & Street.LAYER == 0, "%s leaves the street alone" % light.name)
	var backdrop: Array = main.room.room_model.find_children("WindowView", "MeshInstance3D", true, false)
	check(backdrop.is_empty() or not (backdrop[0] as MeshInstance3D).visible, "the old painted view is hidden")
	main.queue_free()


func test_every_street_material_has_a_shader() -> void:
	var main := await _main()
	var street: Street = main.room.street
	var unknown := []
	for mi: MeshInstance3D in street.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var imported := mi.mesh.surface_get_material(i)
			var mat_name: String = imported.resource_name if imported else ""
			var known: bool = Street.SURFACES.has(mat_name) or mat_name in Street.GLOWS or mat_name in Street.SPECIAL
			if not known:
				unknown.append(mat_name)
			check(mi.get_surface_override_material(i) is ShaderMaterial, "%s/%s has a street shader" % [mi.name, mat_name])
	check(unknown.is_empty(), "every street material is known (not: %s)" % [unknown])
	main.queue_free()


func test_moods_change_the_street() -> void:
	var original: String = Mood.current
	var main := await _main()
	var street: Street = main.room.street
	Mood.set_mood("night", false)
	check(street.mood == "night", "the street follows the mood")
	check(street._lamps.all(func(l: Light3D) -> bool: return l.visible and l.light_energy > 0.0), "street lamps on at night")
	check(float(street.globals.windows_lit) > 0.3, "plenty of windows lit at night")
	Mood.set_mood("rainy", false)
	check(float(street.globals.wet) > 0.5, "the street is wet in the rain")
	Mood.set_mood("golden", false)
	check(street._lamps.all(func(l: Light3D) -> bool: return not l.visible), "street lamps off at golden hour")
	check(street.sun.visible and street.sun.light_energy > 1.0, "the low sun lights the street")
	check(float(street.globals.wet) == 0.0, "dry at golden hour")
	Mood.set_mood(original, false)
	main.queue_free()


func test_signals_take_turns() -> void:
	var main := await _main()
	var street: Street = main.room.street
	var seen_main_green := false
	var seen_cross_green := false
	var t := 0.0
	while t < 60.0:
		street._time = t
		var a := street._signal_state(0)
		var b := street._signal_state(1)
		check(not (a != 0 and b != 0), "never both roads moving at %.1f s" % t)
		seen_main_green = seen_main_green or a == 2
		seen_cross_green = seen_cross_green or b == 2
		t += 0.5
	check(seen_main_green and seen_cross_green, "each road gets a green")
	main.queue_free()


func test_cars_stop_at_red() -> void:
	var main := await _main()
	var street: Street = main.room.street
	street.set_process(false)
	for car in street._cars:
		(car.node as Node).queue_free()
	street._cars.clear()
	# Just after the main street turns red, a car heading for the crossing.
	var t := 0.0
	while street._signal_state(0) != 0 or street._signal_state(1) != 2:
		t += 0.25
		street._time = t
	street._spawn(0)
	check(street._cars.size() == 1, "a car drives in")
	var car: Dictionary = street._cars[0]
	car.x = float(street.layout.cross[0]) - 40.0
	for i in 200:
		street._traffic(0.05, 0)
		street._next_car = [99.0, 99.0]
	var front: float = car.x + car.length * 0.5
	check(front < float(street.layout.cross[0]) - 1.0, "the car waits before the crossing (front at %.1f)" % front)
	check(car.speed < 0.5, "and it has stopped (%.1f m/s)" % car.speed)
	for i in 200:
		street._traffic(0.05, 2)
	check(car.x > float(street.layout.cross[0]), "it goes on green")
	main.queue_free()
