extends Node3D
## Linguini's room. Builds the scene and connects the Moonlight client, the fish,
## the flash cards and the monitor.
##
## Three modes:
## - MENU: the camera frames the monitor from inside the tank; mouse, keyboard and
##   gamepad drive the monitor's menu; cards are released.
## - SWIM: the player is the fish; cards press buttons on the host.
## - EDIT: the tank editor (F2, or Edit tank on the monitor); the fish waits
##   and cards are released while they're rearranged.
##
## Command-line options (after `--`), mostly for testing and screenshots:
##   --swim                 start swimming instead of in the menu
##   --test-video=PATH      loop an H.264/HEVC elementary stream on the monitor
##   --fish=X,Y,Z[,YAW]     place the fish (tank space, yaw in degrees)
##   --gaze                 hold the gaze button
##   --zones                show card trigger zones
##   --room-camera          view through the room camera
##   --overview[=EYE;AT]    view the room from the doorway, or from EYE toward AT
##                          (x,y,z each, in the room model's coordinates)
##   --fov=DEGREES          with --overview, the camera's field of view (default 75)
##   --mood=NAME            night, rainy or golden, just for this run
##   --glyphs=SET           xbox, playstation or nintendo button art, just for this run
##   --quality=LEVEL        low, medium or high graphics, just for this run
##   --edit                 open the tank editor
##   --tracking=STYLE       open the tank cam window (minimal, earnest, over-the-top)
##   --tracking-shot=PATH   with --screenshot, also save the tank cam window
##   --select=N             select card N in the editor
##   --screenshot=PATH      save a screenshot after --delay seconds (default 2) and quit
##   --frames=N             with --screenshot, save N frames --frame-step seconds apart
##                          (default 0.1), as PATH, PATH_01, PATH_02...
##   --tool=NAME [ARGS...]  run res://tools/NAME.gd instead of the room (headless
##                          helpers such as pair and stream_check; this also works
##                          in exported builds, which ignore `-s`)

enum Mode { MENU, SWIM, EDIT }

var client: Node
var room: Dictionary
var fish: Fish
var camera: FishCamera
var cards: CardSystem
var monitor: Monitor
var menu: MonitorMenu
var editor: TankEditor
var decor: TankDecor
var tracking: TrackingCam
var mode := Mode.MENU
var _mode_before_edit := Mode.MENU

var audio: RoomAudio
## The fish's ears: the listener while piloting (the camera's otherwise).
var ears: AudioListener3D
var _water := AABB()
var _has_swum := false
var _args := {}
var _positional := PackedStringArray()


func _ready() -> void:
	_args = _parse_args()
	if _args.has("tool"):
		set_process(false)
		set_process_unhandled_input(false)
		_run_tool(_args.tool)
		return

	if ClassDB.class_exists("MoonlightClient"):
		client = ClassDB.instantiate("MoonlightClient")
		client.name = "MoonlightClient"
		add_child(client)
	else:
		push_error("Linguini: the native extension isn't loaded, so streaming is unavailable. Build it with `scons`.")

	room = RoomBuilder.build(self)
	Quality.attach(room.environment)
	var tank: Node3D = room.tank
	var inner: AABB = room.tank_inner
	var water := AABB(
		tank.global_position + Vector3(inner.position.x, RoomBuilder.GRAVEL_TOP, inner.position.z),
		Vector3(inner.size.x, room.water_level - RoomBuilder.GRAVEL_TOP, inner.size.z))

	_water = water
	fish = _make_fish()
	fish.bounds = water
	tank.add_child(fish)
	fish.position = Vector3(0.3, 0.3, 0.1)
	fish.yaw = PI / 2
	ears = AudioListener3D.new()
	ears.name = "Ears"
	fish.add_child(ears)
	var fish_sounds := FishSounds.new()
	fish_sounds.name = "FishSounds"
	fish.add_child(fish_sounds)

	camera = FishCamera.new()
	camera.fish = fish
	camera.screen = room.screen
	camera.screen_size = room.screen_size
	camera.bounds = water
	add_child(camera)
	camera.make_current()

	cards = CardSystem.new()
	cards.name = "Cards"
	tank.add_child(cards)
	cards.client = client
	cards.fish = fish
	cards.front_z = inner.end.z

	decor = TankDecor.new()
	decor.name = "Decor"
	decor.water = AABB(Vector3(inner.position.x, RoomBuilder.GRAVEL_TOP, inner.position.z),
		Vector3(inner.size.x, room.water_level - RoomBuilder.GRAVEL_TOP, inner.size.z))
	tank.add_child(decor)

	editor = TankEditor.new()
	editor.name = "TankEditor"
	editor.cards = cards
	editor.decor = decor
	editor.water_local = AABB(Vector3(inner.position.x, RoomBuilder.GRAVEL_TOP, inner.position.z),
		Vector3(inner.size.x, room.water_level - RoomBuilder.GRAVEL_TOP, inner.size.z))
	editor.focus = tank.global_position + Vector3(0, 0.28, 0)
	add_child(editor)
	editor.closed.connect(_on_editor_closed)
	if not editor.load_preset(Settings.layout_preset()):
		editor.load_preset(LayoutPresets.DEFAULT)
	editor.preset_changed.connect(func(p: String) -> void: Settings.set_layout_preset(p))

	menu = MonitorMenu.new()
	menu.client = client
	monitor = Monitor.new()
	add_child(monitor)
	monitor.setup(room.screen, room.screen_size, client, menu)

	tracking = TrackingCam.new()
	tracking.fish = fish
	tracking.cards = cards
	tracking.visible = false
	add_child(tracking)
	tracking.follow(room.room_camera)
	set_tracking(Settings.tracking_enabled(), Settings.tracking_style())
	menu.tracking_changed.connect(set_tracking)

	audio = RoomAudio.new()
	audio.name = "RoomAudio"
	add_child(audio)
	audio.setup(room.speakers)

	menu.swim_requested.connect(set_mode.bind(Mode.SWIM))
	menu.resume_requested.connect(set_mode.bind(Mode.SWIM))
	menu.edit_requested.connect(open_editor)
	if client:
		client.stream_started.connect(_on_stream_started)
		client.stream_ended.connect(_on_stream_ended)

	set_mode(Mode.MENU)
	_apply_args()


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	var swimming := mode == Mode.SWIM
	var editing := mode == Mode.EDIT
	_has_swum = _has_swum or swimming
	fish.player_control = swimming
	if not swimming:
		fish.drive(Vector3.ZERO, 0.0)
	# The fish holds still while its cards are rearranged around it.
	fish.set_physics_process(not editing)
	camera.menu_view = not swimming
	# Sound is heard from the fish while piloting it, from the camera otherwise.
	if swimming:
		ears.make_current()
	else:
		ears.clear_current()
	monitor.menu_visible = not swimming
	cards.enabled = swimming
	if editing and not editor.is_open():
		editor.open()
	elif not editing and editor.is_open():
		editor.close()
	if not editing:
		camera.make_current()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if swimming else Input.MOUSE_MODE_VISIBLE


func set_tracking(enabled: bool, style: int) -> void:
	tracking.style = style
	tracking.visible = enabled


func open_editor() -> void:
	if mode == Mode.EDIT:
		return
	_mode_before_edit = mode
	set_mode(Mode.EDIT)


func _on_editor_closed() -> void:
	if mode != Mode.EDIT:
		return
	set_mode(_mode_before_edit)
	if mode == Mode.MENU:
		if client and client.is_streaming():
			menu.show_in_stream()
		else:
			menu.show_home()


func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.EDIT:
		return # the editor handles its own input, including Esc
	if event.is_action_pressed("tracking_cam"):
		get_viewport().set_input_as_handled()
		set_tracking(not tracking.visible, tracking.style)
		Settings.set_tracking(tracking.visible, tracking.style)
		return
	if event.is_action_pressed("edit_tank"):
		get_viewport().set_input_as_handled()
		open_editor()
		return
	if event.is_action_pressed("menu_toggle"):
		get_viewport().set_input_as_handled()
		if mode == Mode.SWIM:
			set_mode(Mode.MENU)
			if client and client.is_streaming():
				menu.show_in_stream()
			else:
				menu.show_home()
		elif _has_swum or (client and client.is_streaming()):
			set_mode(Mode.SWIM)
		return
	if event.is_action_pressed("debug_zones"):
		cards.toggle_zones()
		return
	if mode == Mode.MENU and monitor.forward_input(event, camera):
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set("fish_position", fish.global_position)
	var view := get_viewport().get_camera_3d()
	var underwater := view != null and _water.has_point(view.global_position)
	room.environment.fog_enabled = underwater
	Sound.underwater = underwater or (mode == Mode.SWIM)
	# No HUD: the camera's tally light and the monitor say whether we're live.
	room.moods.live = client != null and client.is_streaming()
	_pump_audio()


func _pump_audio() -> void:
	audio.mode = RoomAudio.Mode.STEREO if Settings.get_stream("audio", "room") == "stereo" else RoomAudio.Mode.ROOM
	if client == null or not client.is_streaming():
		if audio.is_playing():
			audio.stop()
		return
	if not audio.is_playing():
		audio.start()
	var frames := audio.frames_available()
	if frames > 0:
		audio.push(client.pop_audio(frames))


func _on_stream_started() -> void:
	monitor.show_video = true
	set_mode(Mode.SWIM)
	cards.resend()


func _on_stream_ended(_code: int, _message: String) -> void:
	monitor.show_video = false
	set_mode(Mode.MENU)


func _make_fish() -> Fish:
	var f := Fish.new()
	f.name = "Fish"
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.018
	capsule.height = 0.08
	shape.shape = capsule
	shape.rotation.x = PI / 2 # capsules run along Y; the fish runs along Z
	f.add_child(shape)
	f.add_child(FishModel.new(f))
	return f


# --- command line ---

func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			_positional.append(arg)
			continue
		var parts := arg.trim_prefix("--").split("=", true, 1)
		out[parts[0]] = parts[1] if parts.size() > 1 else ""
	return out


func _run_tool(tool_name: String) -> void:
	var path := "res://tools/%s.gd" % tool_name
	if not ResourceLoader.exists(path):
		printerr("No tool named '%s'" % tool_name)
		get_tree().quit(2)
		return
	var tool: Node = load(path).new()
	tool.name = tool_name
	tool.args = _positional
	add_child(tool)


func _apply_args() -> void:
	if _args.has("fish"):
		var v: PackedFloat64Array = _args.fish.split_floats(",")
		fish.position = Vector3(v[0], v[1], v[2])
		if v.size() > 3:
			fish.yaw = deg_to_rad(v[3])
		fish.global_basis = Basis.from_euler(Vector3(0, fish.yaw, 0))
		camera.orbit_yaw = fish.yaw
	if _args.has("test-video") and client:
		client.play_test_file(_args["test-video"], 30.0)
		monitor.show_video = true
	if _args.has("swim"):
		set_mode(Mode.SWIM)
	if _args.has("gaze"):
		Input.action_press("gaze")
	if _args.has("zones"):
		cards.toggle_zones()
	if _args.has("mood"):
		Mood.set_mood(String(_args.mood), false)
	if _args.has("quality"):
		Quality.set_setting(String(_args.quality), false)
	if _args.has("glyphs"):
		Glyphs.set_setting(String(_args.glyphs), false)
	if _args.has("room-camera"):
		(room.room_camera as Camera3D).make_current()
	if _args.has("overview"):
		var eye := Camera3D.new()
		eye.fov = float(_args.get("fov", "75"))
		add_child(eye)
		var shift: Vector3 = room.room_model.position
		var from := Vector3(-1.25, 1.55, 1.55)
		var at := Vector3(0.35, 1.0, -1.4)
		var spec := String(_args.overview)
		if spec.contains(";"):
			var a := spec.get_slice(";", 0).split_floats(",")
			var b := spec.get_slice(";", 1).split_floats(",")
			from = Vector3(a[0], a[1], a[2])
			at = Vector3(b[0], b[1], b[2])
		eye.look_at_from_position(from + shift, at + shift)
		eye.make_current()
	if _args.has("tracking"):
		var i := ["minimal", "earnest", "over-the-top"].find(String(_args.tracking))
		set_tracking(true, i if i >= 0 else TrackingCam.Style.EARNEST)
	if _args.has("edit"):
		open_editor()
		if _args.has("select"):
			var i := int(_args.select)
			if i >= 0 and i < cards.cards.size():
				editor._select(cards.cards[i])
	if _args.has("screenshot"):
		await get_tree().create_timer(float(_args.get("delay", "2"))).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_args.screenshot)
		print("Saved screenshot to ", _args.screenshot)
		# A sequence, for looking at motion: PATH_01.png, PATH_02.png, ...
		var frames := int(_args.get("frames", "1"))
		for i in range(1, frames):
			await get_tree().create_timer(float(_args.get("frame-step", "0.1"))).timeout
			await RenderingServer.frame_post_draw
			var path := String(_args.screenshot).get_basename() + "_%02d.png" % i
			get_viewport().get_texture().get_image().save_png(path)
			print("Saved screenshot to ", path)
		if _args.has("tracking-shot") and tracking.visible:
			tracking.get_texture().get_image().save_png(_args["tracking-shot"])
			print("Saved tank cam screenshot to ", _args["tracking-shot"])
		get_tree().quit()
