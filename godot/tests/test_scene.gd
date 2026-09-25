extends "res://tests/test_case.gd"
## The assembled room: the fish under real physics can't leave the water,
## swimming into a card zone presses it, the follow camera can back out through
## any glass wall and slides in close against the gravel and the surface, and
## the home menu offers a way out.


func _main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add(main)
	await tree.process_frame
	return main


func _physics(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await tree.physics_frame


func test_fish_stays_in_the_water() -> void:
	var main := await _main()
	var fish: Fish = main.fish
	var water: AABB = fish.bounds.grow(0.01)
	var escaped := []
	for dir in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN]:
		fish.drive(dir, 1.0, dir.y)
		for i in 6:
			fish.request_dart()
			await _physics(0.25)
			if not water.has_point(fish.global_position):
				escaped.append("%s at %s" % [dir, fish.global_position])
	check(escaped.is_empty(), "fish left the water: %s" % [escaped])
	main.queue_free()


func test_swimming_into_a_card_presses_it() -> void:
	var main := await _main()
	main.set_mode(main.Mode.SWIM)
	var fish: Fish = main.fish
	var cards: CardSystem = main.cards
	var b_card: FlashCard = cards.cards.filter(func(c: FlashCard) -> bool: return c.input_id == "B")[0]
	# Start in open water below B, facing it, and swim up into its zone.
	fish.player_control = false
	fish.position = Vector3(b_card.position.x, 0.12, 0.12)
	fish.yaw = 0.0
	fish.drive(Vector3.UP, 0.6, 1.0)
	var pressed := false
	for i in 40:
		await _physics(0.05)
		if "B" in cards.held():
			pressed = true
			break
	check(pressed, "swimming up into B's zone presses B (fish at %s, held %s)" % [fish.position, cards.held()])
	main.queue_free()


func test_camera_backs_out_through_every_glass_wall() -> void:
	var main := await _main()
	var cam: FishCamera = main.camera
	var water := cam.bounds
	var mid := water.get_center()
	for dir in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var p: Vector3 = cam._clamp_inside(mid + dir * 2.0, cam.glass_leeway)
		check(not water.has_point(p) and water.grow(cam.glass_leeway + 0.001).has_point(p),
			"out through the %s glass, but not far (%s)" % [dir, p])
	for dir in [Vector3.UP, Vector3.DOWN]:
		var p: Vector3 = cam._clamp_inside(mid + dir * 2.0, cam.glass_leeway)
		check(water.has_point(p), "never through the %s (%s)" % ["surface" if dir.y > 0 else "gravel", p])
	main.queue_free()


func test_home_menu_offers_quit() -> void:
	var main := await _main()
	var buttons: Array = main.menu.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	check("Quit" in buttons, "home menu has a Quit button (buttons: %s)" % [buttons])
	main.queue_free()


func test_camera_slides_in_against_the_surface_and_gravel() -> void:
	var main := await _main()
	var cam: FishCamera = main.camera
	var water := cam.bounds
	for case: Array in [[water.end.y - 0.03, -0.9, "surface"], [water.position.y + 0.03, 0.8, "gravel"]]:
		# The fish near the surface with the camera looking down on it, then
		# near the gravel looking up at it.
		var target := Vector3(water.get_center().x, case[0], water.get_center().z)
		var dir := Basis.from_euler(Vector3(case[1], 0.3, 0.0)) * Vector3(0, 0, 1)
		var d := cam.follow_distance(target, dir)
		check(d < cam.distance * 0.5, "against the %s it slides in close (%.3f m)" % [case[2], d])
		check(d >= cam.min_distance, "but not into the fish (%.3f m)" % d)
		check(water.has_point(target + dir * d), "and stays in the water, keeping its angle")
	# Mid-water it keeps its full distance.
	var mid := water.get_center()
	check(is_equal_approx(cam.follow_distance(mid, Vector3(0, -0.2, 1).normalized()), cam.distance), "mid-water, full distance")
	main.queue_free()
