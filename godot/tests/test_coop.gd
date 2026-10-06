extends "res://tests/test_case.gd"
## Local co-op: more fish join on their own pads, the screen splits, every
## fish presses the same cards (one controller on the host), and players
## leave again.


func _main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add(main)
	await tree.process_frame
	return main


func _press(device: int, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = button
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventJoypadButton
	up.pressed = false
	Input.parse_input_event(up)


func test_join_choose_and_leave() -> void:
	var main := await _main()
	var players: Players = main.players
	var before := players.p1_uses_pad
	players.set_p1_uses_pad(false)
	main.set_mode(main.Mode.SWIM)
	check(players.list.size() == 1 and not players.is_split(), "one player, one full screen")
	_press(7, JOY_BUTTON_START)
	await tree.process_frame
	check(players.list.size() == 2, "Start on a new pad drops a fish in")
	var p2: Players.Player = players.list[1]
	check(p2.input.pad == 7 and p2.choosing, "on that pad, picking its colouring first")
	check(players.is_split(), "and the screen splits")
	check(not p2.fish.player_control, "the new fish waits while its colouring is picked")
	var first_variety := p2.variety
	check(first_variety != players.list[0].variety, "it starts on a colouring nobody has")
	_press(7, JOY_BUTTON_DPAD_RIGHT)
	await tree.process_frame
	check(p2.variety == wrapi(first_variety + 1, 0, FishModel.VARIETIES.size()), "right picks the next colouring")
	_press(7, JOY_BUTTON_A)
	await tree.process_frame
	check(not p2.choosing and p2.fish.player_control, "A starts it swimming")
	main.set_mode(main.Mode.MENU)
	check(not players.is_split(), "the menu is full screen for everyone")
	check(not p2.fish.player_control, "and every fish stops")
	main.set_mode(main.Mode.SWIM)
	check(players.is_split(), "back to the split screen after")
	players.leave(p2)
	await tree.process_frame
	check(players.list.size() == 1 and not players.is_split(), "leaving goes back to one full screen")
	players.set_p1_uses_pad(before)
	main.queue_free()


func test_player_one_takes_the_first_pad() -> void:
	var main := await _main()
	var players: Players = main.players
	var before := players.p1_uses_pad
	players.set_p1_uses_pad(true)
	players.list[0].input.pad = -1
	main.set_mode(main.Mode.SWIM)
	_press(3, JOY_BUTTON_A)
	await tree.process_frame
	check(players.list[0].input.pad == 3 and players.list.size() == 1, "player 1 picks up the first pad used")
	_press(5, JOY_BUTTON_START)
	await tree.process_frame
	check(players.list.size() == 2 and players.list[1].input.pad == 5, "a second pad's Start joins")
	players.set_p1_uses_pad(before)
	main.queue_free()


func test_every_fish_presses_the_cards() -> void:
	var main := await _main()
	var players: Players = main.players
	var cards: CardSystem = main.cards
	main.set_mode(main.Mode.SWIM)
	var p2 := players.join(9)
	p2.choosing = false
	# Player 1 far off; player 2 in front of the first card.
	var card := cards.cards[0]
	main.fish.position = Vector3(0.45, 0.45, 0.2)
	p2.fish.position = Vector3(card.position.x, card.position.y, (card.position.z + 0.25) / 2.0)
	main.fish.pose_effort = 0.0
	p2.fish.pose_effort = 0.0
	for i in 5:
		await tree.physics_frame
	check(card.active, "a card presses for whichever fish is in front of it")
	for id in card.binding.inputs:
		check(id in cards.held(), "%s goes to the one controller" % id)
	main.queue_free()


func test_fish_bump_and_are_tracked() -> void:
	var main := await _main()
	var players: Players = main.players
	main.set_mode(main.Mode.SWIM)
	var p2 := players.join(9)
	p2.choosing = false
	main.fish.position = Vector3(0.0, 0.3, 0.0)
	p2.fish.position = Vector3(0.0, 0.3, 0.0) + Vector3(0.0, 0.0, 0.01)
	main.fish.player_control = false
	p2.fish.player_control = false
	for i in 10:
		await tree.physics_frame
	check(main.fish.global_position.distance_to(p2.fish.global_position) > 0.02, "fish don't swim through each other (%.3f m apart)" % main.fish.global_position.distance_to(p2.fish.global_position))
	main.set_tracking(true, TrackingCam.Style.EARNEST)
	p2.fish.position = Vector3(-0.3, 0.3, 0.1)
	main.fish.position = Vector3(0.3, 0.3, 0.1)
	for i in 3:
		await tree.process_frame
	check(main.tracking.other_boxes.size() == 1, "the tank cam boxes the second fish too")
	main.set_tracking(false, TrackingCam.Style.EARNEST)
	main.queue_free()


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


func test_coop_page_columns() -> void:
	var main := await _main()
	var players: Players = main.players
	var p1: Players.Player = players.list[0]
	var p2 := players.join(9)
	main.set_mode(main.Mode.MENU)
	main.menu.show_coop()
	await tree.process_frame
	var page: CoopPage = main.menu.find_children("CoopPage", "", true, false)[0]
	check(page.get_child_count() == Players.MAX, "a column for every player slot")
	check(not p2.choosing, "a player who joined here picks their fish here")
	var p1_variety := p1.variety
	var p2_variety := p2.variety
	# Player 2's pad works player 2's column only.
	_press(9, JOY_BUTTON_DPAD_RIGHT)
	await tree.process_frame
	check(p2.variety == wrapi(p2_variety + 1, 0, FishModel.VARIETIES.size()) and p1.variety == p1_variety,
		"player 2's right turns player 2's fish carousel, not player 1's")
	_press(9, JOY_BUTTON_DPAD_DOWN)
	_press(9, JOY_BUTTON_A)
	await tree.process_frame
	check(page.cursor(2) == 1 and page.cursor(1) == 0, "each column keeps its own cursor")
	check(p2.steering == "camera" and p2.fish.steering == "camera" and p1.steering == "fish",
		"steering is each player's own (%s, %s)" % [p1.steering, p2.steering])
	# Player 1's keyboard works player 1's column.
	_key(KEY_DOWN)
	_key(KEY_DOWN)
	_key(KEY_RIGHT)
	await tree.process_frame
	check(p1.invert_y and main.camera.invert_y and not p2.invert_y, "player 1 inverts their own look")
	players.set_invert_y(p1, false)
	players.set_steering(p2, "fish")
	# B from any player goes back.
	_press(9, JOY_BUTTON_B)
	await tree.process_frame
	check(not main.menu.is_coop_shown(), "B goes back")
	players.leave(p2)
	main.queue_free()
