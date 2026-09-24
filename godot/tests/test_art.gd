extends "res://tests/test_case.gd"
## The generated models agree with the game's numbers, and the quality presets
## switch their effects on and off.


func _main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add(main)
	await tree.process_frame
	return main


func _surface_vertices(mesh: Mesh, material_name: String) -> PackedVector3Array:
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m and m.resource_name == material_name:
			return mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
	return PackedVector3Array()


func test_tank_matches_room_builder() -> void:
	var scene: Node3D = load("res://art/tank.glb").instantiate()
	add(scene)
	var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	check(mi.global_position.is_zero_approx(), "the tank model's origin is the inside bottom of the tank (%s)" % mi.global_position)
	var glass := _surface_vertices(mi.mesh, "Glass")
	check(not glass.is_empty(), "the tank has glass")
	var inner := RoomBuilder.TANK_INNER
	var x_faces := 0
	var z_faces := 0
	for v in glass:
		if absf(absf(v.x) - inner.end.x) < 0.001:
			x_faces += 1
		if absf(absf(v.z) - inner.end.z) < 0.001:
			z_faces += 1
	check(x_faces > 0 and z_faces > 0, "the glass's inner faces are where the fish's walls are (%d, %d vertices)" % [x_faces, z_faces])
	var gravel := _surface_vertices(mi.mesh, "Gravel")
	var top := 0.0
	var n := 0
	for v in gravel:
		if v.y > 0.01:
			top += v.y
			n += 1
	check(n > 0 and absf(top / n - RoomBuilder.GRAVEL_TOP) < 0.004, "the gravel averages %.3f m deep, the fish's floor is at %.3f" % [top / maxi(n, 1), RoomBuilder.GRAVEL_TOP])
	scene.queue_free()


func test_fish_model() -> void:
	var main := await _main()
	var model: FishModel = main.fish.get_children().filter(func(c: Node) -> bool: return c is FishModel)[0]
	var box := model.local_aabb()
	check(box.has_point(Vector3.ZERO), "the fish's origin (the point cards test) is inside its body")
	check(box.size.z > 0.09 and box.size.z < 0.125, "nose to tail about 11 cm, long tail included (%.3f)" % box.size.z)
	check(box.position.z < -0.02 and box.end.z > 0.05, "facing -Z with the tail toward +Z (%s)" % box)
	main.queue_free()


func test_quality_presets() -> void:
	var original: String = Quality.setting
	var main := await _main()
	var gravel_mat: Material = null
	for mi: MeshInstance3D in main.room.tank.get_node("TankModel").find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_material(i) and mi.mesh.surface_get_material(i).resource_name == "Gravel":
				gravel_mat = mi.get_surface_override_material(i)
	var surface: MeshInstance3D = main.room.water_surface
	var env: Environment = main.room.environment

	Quality.set_setting("low")
	check(Quality.level == Quality.Level.LOW, "Low selects the low preset")
	check(gravel_mat.next_pass == null, "no caustics on Low")
	check((surface.material_override as ShaderMaterial).shader == RoomBuilder.WATER_LOW_SHADER, "the water skips screen refraction on Low")
	check(not env.ssao_enabled and not env.glow_enabled, "no SSAO or glow on Low")
	check(main.get_viewport().scaling_3d_scale < 1.0, "Low renders at a lower scale")

	Quality.set_setting("high")
	check(gravel_mat.next_pass != null, "caustics on High")
	check((surface.material_override as ShaderMaterial).shader == RoomBuilder.WATER_SHADER, "refracting water on High")
	check(env.ssao_enabled and env.glow_enabled, "SSAO and glow on High")
	check(main.get_viewport().msaa_3d == Viewport.MSAA_4X, "4x MSAA on High")

	Quality.set_setting(original)
	check(Quality.setting == original, "the setting is restored")
	main.queue_free()
