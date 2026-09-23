extends Node
## Headless end-to-end check against a paired host: launch an app, stream for a
## while, and report what arrived.
##   godot --headless --path godot -- --tool=stream_check HOST [APP] [SECONDS] [SNAPSHOT.png]
##
## Reports decoded video (size, fps, decoder), audio frames received, and taps
## the A button on the virtual gamepad. Saves the luma plane of the last frame as
## a greyscale PNG if a path is given. Quits the app on the host afterwards.

## Positional command-line arguments, set by main.gd before the tool starts.
var args := PackedStringArray()

var client: Node
var host: String
var app_name: String
var seconds: float
var snapshot: String


func _ready() -> void:
	host = args[0] if args.size() > 0 else "127.0.0.1"
	app_name = args[1] if args.size() > 1 else "Desktop"
	seconds = float(args[2]) if args.size() > 2 else 15.0
	snapshot = args[3] if args.size() > 3 else ""

	client = ClassDB.instantiate("MoonlightClient")
	add_child(client)
	client.request_failed.connect(func(request: String, message: String) -> void:
		print("FAILED (%s): %s" % [request, message])
		get_tree().quit(1))
	client.stream_stage.connect(func(stage: String) -> void: print("  stage: ", stage))
	client.stream_ended.connect(func(code: int, message: String) -> void:
		if code != 0:
			print("Stream ended: %s (%d)" % [message, code]))
	_run.call_deferred()


func _run() -> void:
	print("Connecting to %s…" % host)
	client.connect_host(host)
	var info: Dictionary = (await client.host_ready)
	if not info.paired:
		print("Not paired; run the pair tool first.")
		get_tree().quit(1)
		return

	client.fetch_apps()
	var apps: Array = await client.apps_ready
	var matches := apps.filter(func(a: Dictionary) -> bool: return a.name == app_name)
	if matches.is_empty():
		print("No app named '%s'. Apps: %s" % [app_name, apps.map(func(a: Dictionary) -> String: return a.name)])
		get_tree().quit(1)
		return

	var options := {"width": 1280, "height": 720, "fps": 60, "bitrate_kbps": 10000, "codec": "auto"}
	print("Launching '%s' at %dx%d@%d…" % [app_name, options.width, options.height, options.fps])
	var launched := Time.get_ticks_msec()
	client.start_stream(matches[0].id, options)
	await client.stream_started
	print("Stream started after %.1f s" % ((Time.get_ticks_msec() - launched) / 1000.0))

	var audio_frames := 0
	var first_frame_ms := -1
	var started := Time.get_ticks_msec()
	var pressed_at := started + 3000
	var released := false
	var pressed := false
	var peak_fps := 0.0
	while Time.get_ticks_msec() - started < seconds * 1000.0 and client.is_streaming():
		await get_tree().process_frame
		audio_frames += client.pop_audio(48000).size()
		if first_frame_ms < 0 and client.has_video():
			first_frame_ms = Time.get_ticks_msec() - started
			print("First frame after %d ms: %s via %s" % [first_frame_ms, client.get_video_size(), client.get_decoder_name()])
		peak_fps = maxf(peak_fps, client.get_video_fps())
		var now := Time.get_ticks_msec()
		if not pressed and now >= pressed_at:
			pressed = true
			client.send_controller_state(0x1000, 0, 0, 0, 0, 0, 0) # A
		elif pressed and not released and now >= pressed_at + 300:
			released = true
			client.send_controller_state(0, 0, 0, 0, 0, 0, 0)

	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	print("\nResults over %.1f s:" % elapsed)
	print("  video:  %s, %.0f fps now, %.0f fps peak, decoder %s" % [
		client.get_video_size() if client.has_video() else "NONE", client.get_video_fps(), peak_fps, client.get_decoder_name()])
	print("  colour: %s, %s range" % ["BT.709" if client.is_bt709() else "BT.601", "full" if client.is_full_range() else "limited"])
	print("  audio:  %d frames (%.1f s of 48 kHz stereo)" % [audio_frames, audio_frames / 48000.0])
	print("  input:  A tapped: %s" % released)

	if snapshot != "" and client.has_video():
		var y: Image = client.get_y_texture().get_image()
		var grey := Image.create_from_data(y.get_width(), y.get_height(), false, Image.FORMAT_L8, y.get_data())
		grey.save_png(snapshot)
		print("  luma snapshot: ", snapshot)

	print("Quitting '%s' on the host…" % app_name)
	client.stop_stream(true)
	await get_tree().create_timer(3.0).timeout
	get_tree().quit(0 if client.has_video() else 1)
