extends "res://tests/test_case.gd"
## The native MoonlightClient: decode path, host requests.
##
## Set LINGUINI_TEST_HOST to a Sunshine/GFE address to also test talking to a
## real host (unpaired is fine).

const FIXTURE := "res://tests/fixtures/solid.h264"
## A solid colour, encoded as BT.709 limited range by the fixture command below.
const FIXTURE_RGB := Color8(0x33, 0x66, 0xCC)


func _client() -> Node:
	var client: Node = ClassDB.instantiate("MoonlightClient")
	client.key_directory = "user://test_keys"
	add(client)
	return client


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await tree.process_frame
	return condition.call()


func _ensure_fixture() -> bool:
	if FileAccess.file_exists(FIXTURE):
		return true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/fixtures"))
	var out := []
	var code := OS.execute("ffmpeg", [
		"-y", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=0x3366CC:s=320x240:r=30:d=1",
		"-vf", "scale=out_color_matrix=bt709:out_range=tv", "-colorspace", "bt709", "-color_range", "tv",
		"-pix_fmt", "yuv420p", "-c:v", "libx264", "-bsf:v", "h264_mp4toannexb", "-f", "h264",
		ProjectSettings.globalize_path(FIXTURE)], out, true)
	return code == 0


func test_extension_loaded() -> void:
	check(ClassDB.class_exists("MoonlightClient"), "MoonlightClient is registered")


func test_decode_to_planes() -> void:
	if not _ensure_fixture():
		check(false, "couldn't generate %s (is ffmpeg installed?)" % FIXTURE)
		return
	var client := _client()
	client.play_test_file(FIXTURE, 60.0)
	var ok: bool = await _wait_for(func() -> bool: return client.has_video(), 5.0)
	check(ok, "test stream produces video")
	if ok:
		check(client.get_video_size() == Vector2i(320, 240), "video size %s" % client.get_video_size())
		check(client.is_bt709() and not client.is_full_range(), "BT.709 limited range detected")
		var y: Image = client.get_y_texture().get_image()
		var uv: Image = client.get_uv_texture().get_image()
		check(y.get_format() == Image.FORMAT_R8 and uv.get_format() == Image.FORMAT_RG8, "Y is R8, UV is RG8")
		check(uv.get_size() == Vector2i(160, 120), "chroma is half resolution")
		# Expected BT.709 limited-range encoding of FIXTURE_RGB.
		var r := FIXTURE_RGB.r8
		var g := FIXTURE_RGB.g8
		var b := FIXTURE_RGB.b8
		var ey := 16.0 + 0.1826 * r + 0.6142 * g + 0.0620 * b
		var eu := 128.0 - 0.1006 * r - 0.3386 * g + 0.4392 * b
		var ev := 128.0 + 0.4392 * r - 0.3989 * g - 0.0403 * b
		var py := y.get_pixel(160, 120).r8
		var puv := uv.get_pixel(80, 60)
		check(absf(py - ey) <= 3, "Y %d vs expected %.0f" % [py, ey])
		check(absf(puv.r8 - eu) <= 3 and absf(puv.g8 - ev) <= 3,
			"UV (%d, %d) vs expected (%.0f, %.0f): U must be first" % [puv.r8, puv.g8, eu, ev])
		await _wait_for(func() -> bool: return client.get_video_fps() > 0.0, 2.0)
		check(client.get_decoder_name().contains("h264"), "decoder name: " + client.get_decoder_name())
	client.queue_free()


func test_unreachable_host_fails_quickly() -> void:
	var client := _client()
	var result := []
	client.request_failed.connect(func(req: String, msg: String) -> void: result.append([req, msg]))
	client.host_ready.connect(func(info: Dictionary) -> void: result.append(["ready", info]))
	var started := Time.get_ticks_msec()
	client.connect_host("192.0.2.1") # TEST-NET-1, never routable
	await _wait_for(func() -> bool: return not result.is_empty(), 12.0)
	check(result.size() == 1 and result[0][0] == "connect", "connect fails with request_failed (%s)" % [result])
	check(Time.get_ticks_msec() - started < 9000, "unreachable host fails within the connect timeout")
	var keys := ProjectSettings.globalize_path("user://test_keys")
	check(FileAccess.file_exists(keys + "/client.pem") and FileAccess.file_exists(keys + "/key.pem"),
		"client certificate generated in the key directory")
	client.queue_free()


func test_real_host() -> void:
	var address := OS.get_environment("LINGUINI_TEST_HOST")
	if address == "":
		print("         (skipped: set LINGUINI_TEST_HOST to test against a real host)")
		return
	var client := _client()
	var result := []
	client.request_failed.connect(func(req: String, msg: String) -> void: result.append([req, msg]))
	client.host_ready.connect(func(info: Dictionary) -> void: result.append(["ready", info]))
	client.connect_host(address)
	await _wait_for(func() -> bool: return not result.is_empty(), 10.0)
	check(not result.is_empty() and result[0][0] == "ready", "host answers serverinfo (%s)" % [result])
	if not result.is_empty() and result[0][0] == "ready":
		var info: Dictionary = result[0][1]
		print("         host: ", info)
		check(info.app_version != "", "host reports its version")
	client.queue_free()
