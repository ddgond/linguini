extends "res://tests/test_case.gd"
## The assembled room: the fish under real physics can't leave the water,
## swimming into a card zone presses it, and the home menu offers a way out.


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


func test_home_menu_offers_quit() -> void:
	var main := await _main()
	var buttons: Array = main.menu.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	check("Quit" in buttons, "home menu has a Quit button (buttons: %s)" % [buttons])
	main.queue_free()
