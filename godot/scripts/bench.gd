class_name Bench
extends Node
## A fixed tour for measuring performance (--bench; tools/bench.sh). Each view
## is held in each mood at each quality level, without and then with a stream
## on the monitor, and timed: frame ms (vsync off) and GPU ms (every
## viewport's measured render time, so split views and the monitor's menu
## count). Prints a Markdown table and quits.
##
## The views: the menu (in the tank, facing the monitor), swimming (toward the
## back glass and the street), the tank editor, two-player split screen, the
## room from the doorway and the street from the window.
##
## The stream is a 1080p60 H.264 clip looped through the real decoder, made
## with ffmpeg the first time (user://bench_1080p60.h264).
##
## --quality=LEVEL and --mood=NAME limit the tour to that level or mood;
## --bench=VIEWS (comma-separated) to those views; --bench-stream=off or on to
## one half; --bench-size=WxH sets the window (default 1920x1080).
## --bench-off=PARTS leaves parts out to see what they cost (_leave_out).

const VIEWS := ["menu", "swim", "editor", "split", "room", "window"]
const WARM_UP := 1.5
const MEASURE := 3.0
const CLIP := "user://bench_1080p60.h264"

var main: Node
var views: Array = VIEWS
var levels: Array = ["low", "medium", "high"]
var moods: Array = Mood.NAMES
var streams: Array = [false, true]
var size := Vector2i(1920, 1080)
## Parts to leave out, to see what they cost (--bench-off).
var off: Array = []

var _eye: Camera3D
var _guest: Players.Player


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	_eye = Camera3D.new()
	_eye.name = "BenchEye"
	main.add_child(_eye)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	var vp_size := get_viewport().get_visible_rect().size
	print("Linguini bench: %s (%s), %dx%d window, vsync off" % [RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), vp_size.x, vp_size.y])
	print("Averages over %.0f s per view after %.1f s to settle; worst = the slowest 5%% of frames.\n" % [MEASURE, WARM_UP])
	if not off.is_empty():
		print("Left out: %s\n" % ", ".join(off))
	_header()
	for stream: bool in streams:
		if stream and not _start_stream():
			print("(no stream: couldn't make %s; is ffmpeg installed?)" % CLIP)
			continue
		for level: String in levels:
			Quality.set_setting(level, false)
			for mood: String in moods:
				Mood.set_mood(mood, false)
				_leave_out()
				for view: String in views:
					_show(view)
					await get_tree().create_timer(WARM_UP).timeout
					var r: Dictionary = await _measure()
					_row([view, mood, level, "on" if stream else "off", r.frame, r.worst, r.gpu])
	print("\nDone.")
	# Now and then Godot hangs on its way out (in its own shutdown, so a timer
	# wouldn't fire): the table is out, so a thread ends the process if it's
	# still here in a few seconds.
	var watchdog := Thread.new()
	watchdog.start(func() -> void:
		OS.delay_msec(5000)
		OS.kill(OS.get_process_id()))
	get_tree().quit()


func _header() -> void:
	print("| view | mood | quality | stream | frame ms | worst ms | GPU ms |")
	print("|---|---|---|---|---:|---:|---:|")


func _row(cells: Array) -> void:
	var out := PackedStringArray()
	for c: Variant in cells:
		out.append("%.1f" % c if c is float else str(c))
	print("| " + " | ".join(out) + " |")


func _start_stream() -> bool:
	if main.client == null:
		return false
	var path := ProjectSettings.globalize_path(CLIP)
	if not FileAccess.file_exists(CLIP):
		# Busy enough that the encoder can't coast: a moving test pattern.
		var args := ["-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=60",
			"-t", "10", "-c:v", "libx264", "-preset", "veryfast", "-b:v", "20M", "-pix_fmt", "yuv420p",
			"-bsf:v", "h264_mp4toannexb", "-f", "h264", path]
		if OS.execute("ffmpeg", args) != 0 or not FileAccess.file_exists(CLIP):
			return false
	main.client.play_test_file(CLIP, 60.0)
	main.monitor.show_video = true
	return true


## Sets up one view: the mode, who's playing and which camera looks.
func _show(view: String) -> void:
	var players: Players = main.players
	if view != "split" and _guest:
		players.leave(_guest)
		_guest = null
	var swimming := view in ["swim", "split"]
	main.set_mode(main.Mode.SWIM if swimming else main.Mode.MENU)
	if view == "editor":
		main.open_editor()  # its own camera, from the room toward the tank
	var fish: Fish = main.fish
	var cam: FishCamera = main.camera
	match view:
		"menu":
			cam.make_current()
		"swim":
			# Toward the back glass, the window and the street beyond it.
			_place(fish, Vector3(0.1, 0.22, 0.12), 160.0)
			cam.make_current()
		"editor":
			pass
		"window":
			_look(Vector3(-0.15, 1.45, 0.3), Vector3(-0.15, 1.5, -1.8))
		"room":
			_look(Vector3(-1.25, 1.55, 1.55), Vector3(0.35, 1.0, -1.4))
		"split":
			_place(fish, Vector3(0.1, 0.22, 0.12), 160.0)
			if _guest == null:
				_guest = players.join(100)
				_guest.choosing = false
				players.set_mode(true, false)
				_place(_guest.fish, Vector3(-0.2, 0.3, 0.05), -60.0)


func _place(fish: Fish, at: Vector3, yaw_deg: float) -> void:
	fish.position = at
	fish.yaw = deg_to_rad(yaw_deg)
	fish.global_basis = Basis.from_euler(Vector3(0, fish.yaw, 0))
	fish.pose_effort = 0.3
	for p: Players.Player in main.players.list:
		if p.fish == fish:
			p.camera.orbit_yaw = fish.yaw


## A camera of our own, placed in the room model's coordinates.
func _look(from: Vector3, at: Vector3) -> void:
	var shift: Vector3 = main.room.room_model.position
	_eye.fov = 75.0
	_eye.look_at_from_position(from + shift, at + shift)
	_eye.make_current()


func _measure() -> Dictionary:
	var vps := _viewports()
	for vp in vps:
		RenderingServer.viewport_set_measure_render_time(vp, true)
	var frames: Array[float] = []
	var gpu := 0.0
	var t := 0.0
	await RenderingServer.frame_post_draw
	var last := Time.get_ticks_usec()
	while t < MEASURE:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		t += ms / 1000.0
		frames.append(ms)
		for vp in vps:
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var n := maxf(frames.size(), 1)
	var total := 0.0
	for f in frames:
		total += f
	frames.sort()
	var tail := frames.slice(int(frames.size() * 0.95))
	var worst := 0.0
	for f in tail:
		worst += f
	return {"frame": total / n, "worst": worst / maxf(tail.size(), 1), "gpu": gpu / n}


## Every viewport drawing this frame: the window, split views, the monitor's
## menu, card faces and the tank cam window.
func _viewports() -> Array[RID]:
	var out: Array[RID] = [get_viewport().get_viewport_rid()]
	for vp: Viewport in get_tree().root.find_children("*", "Viewport", true, false):
		out.append(vp.get_viewport_rid())
	return out


## Hides or switches off each part named in `off`.
func _leave_out() -> void:
	var room: Dictionary = main.room
	var street: Street = room.street
	for part: String in off:
		match part:
			"street":
				street.visible = false
			"rain":
				for n in street.find_children("Rain", "MeshInstance3D", false, false):
					n.visible = false
			"people":
				for n in street.find_children("Walker", "Node3D", false, false):
					n.visible = false
			"cars":
				for n in street.find_children("Car", "Node3D", false, false):
					n.visible = false
			"street-lights":
				for n: Light3D in street.find_children("*", "Light3D", true, false):
					n.visible = false
			"glass":
				room.room_model.find_child("WindowGlass", true, false).visible = false
			"room":
				room.room_model.visible = false
			"tank":
				room.tank.visible = false
			"lights":
				for n: Light3D in get_tree().root.find_children("*", "Light3D", true, false):
					if not street.is_ancestor_of(n):
						n.visible = false
			"shadows":
				for n: Light3D in get_tree().root.find_children("*", "Light3D", true, false):
					n.shadow_enabled = false
			"glow":
				room.environment.glow_enabled = false
			"fog":
				room.environment.volumetric_fog_enabled = false
				room.environment.fog_enabled = false
			"half":
				get_viewport().scaling_3d_scale = 0.5
			"street-flat", "street-lit":
				# The street's own shaders swapped for flat colour, unshaded or
				# lit: geometry, Godot's lighting or the shaders themselves?
				var flat := Shader.new()
				flat.code = "shader_type spatial;\n%s\nvoid fragment() { ALBEDO = vec3(0.3); }\n" % (
					"render_mode unshaded;" if part == "street-flat" else "")
				for mi: MeshInstance3D in street.get_node("Model").find_children("*", "MeshInstance3D", true, false):
					for i in mi.mesh.get_surface_count():
						var active := mi.get_active_material(i)
						if active is ShaderMaterial:
							(active as ShaderMaterial).shader = flat
			"lod":
				get_viewport().mesh_lod_threshold = 8.0
			_ when part.begins_with("surface:") or part.begins_with("plain:"):
				# Surfaces by their model's material name, drawn as nothing
				# (surface:) or as a plain lit grey (plain:, which keeps what's
				# behind hidden, so it's the fairer price of a shader).
				var hole := Shader.new()
				hole.code = ("shader_type spatial;\nrender_mode unshaded;\nvoid fragment() { discard; }\n"
					if part.begins_with("surface:") else "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(0.3); }\n")
				var mat_name := part.get_slice(":", 1)
				for mi: MeshInstance3D in get_tree().root.find_children("*", "MeshInstance3D", true, false):
					for i in mi.mesh.get_surface_count() if mi.mesh else 0:
						var m := mi.mesh.surface_get_material(i)
						if m == null or m.resource_name != mat_name:
							continue
						var active := mi.get_active_material(i)
						if active is ShaderMaterial:
							(active as ShaderMaterial).shader = hole
						else:
							var mat := ShaderMaterial.new()
							mat.shader = hole
							mi.set_surface_override_material(i, mat)
			_:
				# Any other name: every node by that name (a light, a tank part...).
				var found := get_tree().root.find_children(part, "Node3D", true, false)
				if found.is_empty():
					push_warning("Bench: nothing called %s to leave out" % part)
				for n: Node3D in found:
					n.visible = false
