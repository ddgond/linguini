extends "res://tests/test_case.gd"
## Game audio: speakers in the room, the light underwater muffle, plain stereo.


func _audio() -> RoomAudio:
	var audio := RoomAudio.new()
	add(audio)
	audio.setup([Vector3(1.66, 0.87, -0.6), Vector3(1.66, 0.87, 0.6)])
	return audio


func _run(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await tree.process_frame
		t += tree.root.get_process_delta_time()


func test_each_speaker_plays_one_channel() -> void:
	var pcm := PackedVector2Array([Vector2(0.5, -0.25), Vector2(0.1, 0.9)])
	var left := RoomAudio.split_channel(pcm, 0)
	var right := RoomAudio.split_channel(pcm, 1)
	check(left == PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.1, 0.1)]), "the left speaker gets the left channel (%s)" % left)
	check(right == PackedVector2Array([Vector2(-0.25, -0.25), Vector2(0.9, 0.9)]), "the right speaker gets the right channel (%s)" % right)


func test_underwater_muffles_lightly_and_clears() -> void:
	var audio := _audio()
	var water := AudioServer.get_bus_index("Water")
	check(water >= 0, "the Water bus exists")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(RoomAudio.BUS)) == &"Water", "the stream goes through the water")

	Sound.underwater = true
	await _run(1.5)
	check(Sound.muffle_hz() < 4500.0 and Sound.muffle_hz() > 2500.0, "underwater, it's muffled lightly (%.0f Hz)" % Sound.muffle_hz())
	check(AudioServer.is_bus_effect_enabled(water, 0), "and the filter is on")

	Sound.underwater = false
	await _run(1.5)
	check(Sound.muffle_hz() > 15000.0, "surfacing opens it back up (%.0f Hz)" % Sound.muffle_hz())
	check(not AudioServer.is_bus_effect_enabled(water, 0), "and switches it off")

	audio.mode = RoomAudio.Mode.STEREO
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(RoomAudio.BUS)) == &"Master", "plain stereo skips the water")
	audio.mode = RoomAudio.Mode.ROOM
	audio.queue_free()


func test_mode_switch_keeps_playing() -> void:
	var audio := _audio()
	audio.start()
	check(audio.is_playing(), "room audio starts")
	audio.mode = RoomAudio.Mode.STEREO
	check(audio.is_playing(), "switching to stereo mid-stream keeps playing")
	audio.stop()
	check(not audio.is_playing(), "and stops")
	audio.queue_free()


func test_speakers_are_by_the_monitor() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add(main)
	await tree.process_frame
	var screen: Node3D = main.room.screen
	var speakers: Array = main.audio.find_children("*", "AudioStreamPlayer3D", false, false)
	check(speakers.size() == 2, "two speakers")
	for s: AudioStreamPlayer3D in speakers:
		check(s.global_position.distance_to(screen.global_position) < 1.0, "speaker %s is next to the monitor" % s.global_position)
		check(s.bus == RoomAudio.BUS, "and plays through the Game bus")
	main.queue_free()
