extends "res://tests/test_case.gd"
## Feel and sound: the mixer, where you hear from, what makes sounds, the dart
## kick and the water's motes and shafts.


func _main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add(main)
	await tree.process_frame
	return main


func _sounds_playing(sound_name: String) -> int:
	return Sound.get_children().filter(func(n: Node) -> bool:
		return n is AudioStreamPlayer3D and n.stream == Sound.stream(sound_name)).size()


func test_buses_and_volumes() -> void:
	for pair: Array in [["Game", "Water"], ["Room", "Water"], ["Water", "Master"], ["UI", "Master"]]:
		var bus := AudioServer.get_bus_index(pair[0])
		check(bus >= 0 and AudioServer.get_bus_send(bus) == StringName(pair[1]), "%s feeds %s" % pair)
	var original := Sound.volume("room")
	Sound.set_volume("room", 0.5)
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Room")) - linear_to_db(0.5)) < 0.01, "a slider sets its bus volume")
	check(is_equal_approx(float(Settings.get_value("audio", "volume_room", 1.0)), 0.5), "and it's remembered")
	Sound.set_volume("room", 0.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Room")), "all the way down mutes it")
	Sound.set_volume("room", original)


func test_heard_from_the_fish_while_piloting() -> void:
	var main := await _main()
	var ears: AudioListener3D = main.ears
	check(not ears.is_current(), "in the menu, the camera listens")
	main.set_mode(main.Mode.SWIM)
	await tree.process_frame
	check(ears.is_current(), "piloting, the fish's ears listen")
	check(Sound.underwater, "and the fish is always underwater")
	main.set_mode(main.Mode.MENU)
	check(not ears.is_current(), "back in the menu, the camera again")
	main.queue_free()


func test_cards_tap() -> void:
	var main := await _main()
	main.set_mode(main.Mode.SWIM)
	var cards: CardSystem = main.cards
	var before := _sounds_playing("card_press")
	cards.update(cards._zones[0].get_center(), 0.016)
	check(_sounds_playing("card_press") == before + 1, "a card taps as it presses")
	var releases := _sounds_playing("card_release")
	for i in 20:
		cards.update(Vector3(0, 10, 0), 0.016)
	check(_sounds_playing("card_release") == releases + 1, "and makes a lighter one on release")
	main.queue_free()


func test_tank_and_room_sounds() -> void:
	var main := await _main()
	var decor: TankDecor = main.decor
	var air := decor.add_piece("airstone", Vector3(0, 0.1, 0))
	var filter := decor.add_piece("filter", Vector3(0.3, 0.4, -0.25))
	await tree.process_frame
	check(air.has_node("Loop_bubbles"), "the air stone bubbles")
	check(filter.has_node("Loop_trickle"), "the filter trickles")
	check(main.room.tank.has_node("Loop_tank_hum"), "the tank hums")
	var moods: RoomMoods = main.room.moods
	var original: String = Mood.current
	Mood.set_mood("rainy", false)
	check(moods._tone.has("rain") and moods._tone.rain.playing, "it rains outside on a rainy evening")
	Mood.set_mood("golden", false)
	check(moods._tone.has("birds"), "birds at golden hour")
	Mood.set_mood(original, false)
	main.queue_free()


func test_dart_kick() -> void:
	var main := await _main()
	main.set_mode(main.Mode.SWIM)
	main.fish.darted.emit()
	check(is_equal_approx(main.camera.kick, 1.0), "a dart kicks the camera's FOV")
	var before := _sounds_playing("dart")
	main.fish.darted.emit()
	check(_sounds_playing("dart") == before + 1, "and whooshes")
	main.queue_free()


func test_motes_and_shafts_follow_quality() -> void:
	var original: String = Quality.setting
	var main := await _main()
	var atmosphere: TankAtmosphere = main.room.atmosphere
	Quality.set_setting("low")
	check(atmosphere.motes.amount == TankAtmosphere.MOTES[0] and not atmosphere.shafts[0].visible, "Low: few motes, no shafts")
	Quality.set_setting("high")
	check(atmosphere.motes.amount == TankAtmosphere.MOTES[2] and atmosphere.shafts[0].visible, "High: more motes and the shafts")
	Quality.set_setting(original)
	main.queue_free()


func test_volume_sliders_on_the_monitor() -> void:
	var main := await _main()
	for key in ["master", "game", "room", "ui"]:
		check(not main.menu.find_children("Volume_" + key, "HSlider", true, false).is_empty(), "a %s slider" % key)
	main.queue_free()
