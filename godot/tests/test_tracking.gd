extends "res://tests/test_case.gd"
## The tank cam's fake detector: it tracks the fish, notices when a card hides
## it, and reports what the fish is pressing.


func _main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add(main)
	await tree.process_frame
	return main


func _settle(frames := 10) -> void:
	for i in frames:
		await tree.physics_frame
		await tree.process_frame


func test_tracks_the_fish() -> void:
	var main := await _main()
	var cam: TrackingCam = main.tracking
	main.set_tracking(true, TrackingCam.Style.EARNEST)
	main.set_mode(main.Mode.SWIM)
	var fish: Fish = main.fish
	fish.player_control = false
	var b_card: FlashCard = main.cards.cards.filter(func(c: FlashCard) -> bool: return c.binding.inputs == PackedStringArray(["B"]))[0]
	fish.position = Vector3(b_card.position.x, b_card.position.y, 0.05)
	await _settle(20)
	check(cam.detected, "the fish is detected in open view")
	var expected := cam.camera.unproject_position(fish.global_position)
	check(cam.box.has_point(expected), "the box contains the fish (%s, box %s)" % [expected, cam.box])
	check(cam.box.size.x < 200 and cam.box.size.y < 200, "the box is fish-sized (%s)" % cam.box.size)
	check(cam.confidence > 0.85, "confidence is high in open view (%.2f)" % cam.confidence)
	check(cam.held_text() == "B" and cam.zone_text() == "[B]", "it reports the zone and held input (%s / %s)" % [cam.zone_text(), cam.held_text()])
	check(cam.log_lines.size() > 0 and cam.log_lines[-1].contains("B"), "the press is logged (%s)" % [cam.log_lines])
	main.queue_free()


func test_occlusion_lowers_confidence() -> void:
	var main := await _main()
	var cam: TrackingCam = main.tracking
	main.set_tracking(true, TrackingCam.Style.EARNEST)
	var fish: Fish = main.fish
	fish.set_physics_process(false)
	# Right behind the R_UP card (which stands mid-tank), as seen from the camera.
	var r_up: FlashCard = main.cards.cards.filter(func(c: FlashCard) -> bool: return c.binding.inputs == PackedStringArray(["R_UP"]))[0]
	fish.global_position = r_up.global_position + (r_up.global_position - cam.camera.global_position).normalized() * 0.04
	await _settle(30)
	check(cam.occluded, "the fish behind a card counts as occluded")
	check(cam.confidence < 0.6, "and confidence drops (%.2f)" % cam.confidence)
	main.queue_free()


func test_window_toggle_is_remembered() -> void:
	var was_enabled := Settings.tracking_enabled()
	var was_style := Settings.tracking_style()
	var main := await _main()
	main.menu.tracking_changed.emit(true, TrackingCam.Style.OVER_THE_TOP)
	check(main.tracking.visible and main.tracking.style == TrackingCam.Style.OVER_THE_TOP, "the menu switches the window and its style")
	main.set_tracking(false, TrackingCam.Style.MINIMAL)
	check(not main.tracking.visible, "and can hide it")
	Settings.set_tracking(was_enabled, was_style)
	main.queue_free()
