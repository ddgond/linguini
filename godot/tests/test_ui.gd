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


func test_menu_stays_above_the_taskbar() -> void:
	var main := await _main()
	var menu: MonitorMenu = main.menu
	var taskbar_top: float = (menu.get_node("Taskbar") as Control).get_global_rect().position.y
	menu.show_home("A long error message about the host")
	for i in 12:
		menu._label("Filler", 26, Color.WHITE)
	await tree.process_frame
	await tree.process_frame
	check(menu._window.get_global_rect().end.y <= taskbar_top, "an overfull page scrolls instead of running under the taskbar")
	menu._app_name = "Desktop"
	menu.show_in_stream()
	await tree.process_frame
	await tree.process_frame
	var scroll := menu._page.get_parent().get_parent() as ScrollContainer
	check(not scroll.get_v_scroll_bar().visible, "the in-stream page fits without scrolling")
	for b: Button in menu._page.find_children("*", "Button", true, false):
		check(b.get_global_rect().end.y <= taskbar_top, "%s is above the taskbar" % b.text)
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
	# The box eases after the fish (35% a frame), so give it time to settle.
	for i in 20:
		await tree.process_frame
	var cam: TrackingCam = main.tracking
	check(cam.detected, "the fish is detected")
	check(cam.keypoints.size() == TrackingCam.KEYPOINTS.size(), "every keypoint is placed (%d)" % cam.keypoints.size())
	var inside := 0
	for p: Vector2 in cam.keypoints.values():
		if cam.box.grow(12.0).has_point(p):
			inside += 1
	check(inside == cam.keypoints.size(), "keypoints sit on the fish (%d of %d in its box)" % [inside, cam.keypoints.size()])
	var model: FishModel = main.fish.get_children().filter(func(c: Node) -> bool: return c is FishModel)[0]
	var k := model.keypoints()
	check(k.size() == TrackingCam.KEYPOINTS.size(), "every keypoint is found on the model (%d)" % k.size())
	if k.size() == TrackingCam.KEYPOINTS.size():
		check(k.nose.z < k.eye_l.z and k.eye_l.z < k.tail_base.z and k.tail_base.z < k.tail_tip.z,
			"nose, eyes, tail base and tail tip run front to back")
		check(k.eye_l.x < 0.0 and k.eye_r.x > 0.0 and k.fin_l.x < k.eye_l.x and k.fin_r.x > k.eye_r.x,
			"eyes either side, pectorals reaching out past them")
		check(k.dorsal.y > k.eye_l.y and k.dorsal.y > k.tail_base.y, "the dorsal's tip is the top of the fish")
		check(k.fin_l.z < k.tail_base.z and k.fin_r.z < k.tail_base.z, "the pectorals are in the front half")
	main.set_tracking(false, TrackingCam.Style.EARNEST)
	main.queue_free()



func test_settings_page_focus() -> void:
	var main := await _main()
	main.menu.show_settings()
	await tree.process_frame
	await tree.process_frame
	var focused: Control = main.menu.get_viewport().gui_get_focus_owner()
	check(focused is Stepper and focused.name == "QualityPicker", "the first setting has focus (%s)" % focused)
	main.queue_free()


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


func test_settings_page_by_keyboard() -> void:
	var main := await _main()
	main.set_mode(main.Mode.MENU)
	main.menu.show_settings()
	await tree.process_frame
	await tree.process_frame
	var vp: Viewport = main.menu.get_viewport()
	check(vp.gui_get_focus_owner() != null and vp.gui_get_focus_owner().name == "QualityPicker", "Graphics has focus first")
	_key(KEY_DOWN)
	await tree.process_frame
	var focused: Control = vp.gui_get_focus_owner()
	check(focused != null and focused.name == "MoodPicker", "down moves to Mood (%s)" % focused)
	var mood: Stepper = main.menu.find_children("MoodPicker", "", true, false)[0]
	var before := mood.selected
	var original: String = Mood.current
	_key(KEY_D)
	await tree.process_frame
	check(mood.selected != before, "D (or right) changes the mood")
	Mood.set_mood(original, false)
	_key(KEY_S)
	await tree.process_frame
	focused = vp.gui_get_focus_owner()
	check(focused != null and focused.name == "TankCamWindow", "S goes down the same column, to the tank cam (%s)" % focused)
	_key(KEY_ESCAPE)
	await tree.process_frame
	check(not main.menu.is_settings_shown() and main.mode == main.Mode.MENU, "Esc goes back to the menu's main page")
	main.queue_free()


func test_direct_input_mode() -> void:
	# Which key the host hears: where it is on the keyboard.
	var k := InputEventKey.new()
	k.physical_keycode = KEY_W
	check(DirectInput.virtual_key(k) == 0x57, "W is VK 0x57")
	k.physical_keycode = KEY_F5
	check(DirectInput.virtual_key(k) == 0x74, "F5 is VK_F5")
	k.physical_keycode = KEY_SHIFT
	k.location = KEY_LOCATION_RIGHT
	check(DirectInput.virtual_key(k) == 0xA1, "right Shift is VK_RSHIFT")
	k.physical_keycode = KEY_ESCAPE
	k.ctrl_pressed = true
	k.alt_pressed = true
	check(DirectInput.virtual_key(k) == 0x1B and DirectInput.modifiers(k) == 6, "Esc with Ctrl and Alt held")

	var main := await _main()
	main.set_mode(main.Mode.DIRECT)
	check(main.direct.active and not main.monitor.menu_visible and not main.cards.enabled,
		"direct input: the menu away, the cards released")
	check(not main.direct.fullscreen and main.direct.get_child(0).visible == false, "on the room's monitor at first")
	_key(KEY_F11)
	await tree.process_frame
	check(main.direct.fullscreen and main.get_viewport().disable_3d, "F11: the stream fills the window, the room isn't drawn")
	_key(KEY_F11)
	await tree.process_frame
	check(not main.direct.fullscreen and not main.get_viewport().disable_3d, "F11 again: back on the monitor")
	var quit := InputEventKey.new()
	quit.physical_keycode = KEY_Q
	quit.keycode = KEY_Q
	quit.ctrl_pressed = true
	quit.alt_pressed = true
	quit.shift_pressed = true
	quit.pressed = true
	Input.parse_input_event(quit)
	await tree.process_frame
	check(main.mode == main.Mode.MENU and not main.direct.active, "Ctrl+Alt+Shift+Q leaves it")
	main.queue_free()
