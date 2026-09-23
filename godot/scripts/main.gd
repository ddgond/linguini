extends Node3D
## Linguini's room. Builds the scene and connects the Moonlight client, the fish,
## the flash cards and the monitor.
##
## Two modes:
## - MENU: the camera frames the monitor from inside the tank; mouse, keyboard and
##   gamepad drive the monitor's menu; cards are released.
## - SWIM: the player is the fish; cards press buttons on the host.
##
## Command-line options (after `--`), mostly for testing and screenshots:
##   --swim                 start swimming instead of in the menu
##   --test-video=PATH      loop an H.264/HEVC elementary stream on the monitor
##   --fish=X,Y,Z[,YAW]     place the fish (tank space, yaw in degrees)
##   --gaze                 hold the gaze button
##   --zones                show card trigger zones
##   --room-camera          view through the room camera
##   --screenshot=PATH      save a screenshot after --delay seconds (default 2) and quit
##   --tool=NAME [ARGS...]  run res://tools/NAME.gd instead of the room (headless
##                          helpers such as pair and stream_check; this also works
##                          in exported builds, which ignore `-s`)

enum Mode { MENU, SWIM }

var client: Node
var room: Dictionary
var fish: Fish
var camera: FishCamera
var cards: CardSystem
var monitor: Monitor
var menu: MonitorMenu
var hud: Hud
var mode := Mode.MENU

var _audio: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
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
	var tank: Node3D = room.tank
	var inner: AABB = room.tank_inner
	var water := AABB(
		tank.global_position + Vector3(inner.position.x, RoomBuilder.GRAVEL_TOP, inner.position.z),
		Vector3(inner.size.x, room.water_level - RoomBuilder.GRAVEL_TOP, inner.size.z))

	fish = _make_fish()
	fish.bounds = water
	tank.add_child(fish)
	fish.position = Vector3(0.3, 0.3, 0.1)
	fish.yaw = PI / 2

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
	cards.load_layout("res://data/layouts/default.json")

	menu = MonitorMenu.new()
	menu.client = client
	monitor = Monitor.new()
	add_child(monitor)
	monitor.setup(room.screen, room.screen_size, client, menu)

	hud = Hud.new()
	hud.client = client
	add_child(hud)
	cards.held_changed.connect(hud.set_held)

	_audio = AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 48000
	generator.buffer_length = 0.08
	_audio.stream = generator
	add_child(_audio)

	menu.swim_requested.connect(set_mode.bind(Mode.SWIM))
	menu.resume_requested.connect(set_mode.bind(Mode.SWIM))
	if client:
		client.stream_started.connect(_on_stream_started)
		client.stream_ended.connect(_on_stream_ended)

	set_mode(Mode.MENU)
	_apply_args()


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	var swimming := mode == Mode.SWIM
	_has_swum = _has_swum or swimming
	fish.player_control = swimming
	if not swimming:
		fish.drive(Vector3.ZERO, 0.0)
	camera.menu_view = not swimming
	monitor.menu_visible = not swimming
	cards.enabled = swimming
	hud.visible = swimming
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if swimming else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
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
	room.environment.fog_enabled = camera.is_underwater()
	_pump_audio()


func _pump_audio() -> void:
	if client == null or not client.is_streaming():
		if _audio.playing:
			_audio.stop()
		return
	if not _audio.playing:
		_audio.play()
		_playback = _audio.get_stream_playback()
	var frames := _playback.get_frames_available()
	if frames > 0:
		var pcm: PackedVector2Array = client.pop_audio(frames)
		if not pcm.is_empty():
			_playback.push_buffer(pcm)


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
	if _args.has("room-camera"):
		(room.room_camera as Camera3D).make_current()
		hud.visible = false
	if _args.has("screenshot"):
		await get_tree().create_timer(float(_args.get("delay", "2"))).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_args.screenshot)
		print("Saved screenshot to ", _args.screenshot)
		get_tree().quit()
