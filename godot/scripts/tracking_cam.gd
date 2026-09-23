class_name TrackingCam
extends Window
## The "ML fish tracking" feed: a separate OS window showing the room camera's
## view of the tank with a fake computer-vision overlay, for OBS to capture
## (Window Capture, window title "Linguini Tank Cam").
##
## Nothing here is machine learning. The "detector" is the fish's real position
## projected into the camera, dressed up with a jittering confidence score that
## drops when a card hides the fish from the camera.
##
## Styles (all label the fish plainly, "goldfish 0.97"):
## - MINIMAL: corner-bracket box with its tag, and the held inputs.
## - EARNEST: a straight-faced research tool. Adds a keypoint skeleton (nose,
##   eyes, fins, tail), the trail and heatmap, labelled card zones, inference
##   and latency readouts and a short detection log.
## - OVER_THE_TOP: everything in EARNEST, plus a model banner, a track ID,
##   trajectory prediction, neural activations, intent guesses, a scrolling
##   log, scanlines and the occasional "recalibrating" flicker.

enum Style { MINIMAL, EARNEST, OVER_THE_TOP }

const STYLE_NAMES := ["Minimal", "Earnest", "Over-the-top"]
const SIZE := Vector2i(1280, 720)
const TITLE := "Linguini Tank Cam"
const TRAIL_SECONDS := 2.5
const HEAT_CELLS := Vector2i(48, 27)
const MODEL := "finnet-s v3.2"
const MODEL_XL := "FINNET-XL // research build 0xF15H"
const CLASS_NAME := "goldfish"
## Keypoints, as fractions of the fish's bounds (x across, y up, z nose -1 .. tail +1).
const KEYPOINTS := {
	"nose": Vector3(0, 0, -1), "eye_l": Vector3(-0.45, 0.25, -0.6), "eye_r": Vector3(0.45, 0.25, -0.6),
	"dorsal": Vector3(0, 1, -0.05), "fin_l": Vector3(-1, -0.35, -0.2), "fin_r": Vector3(1, -0.35, -0.2),
	"tail_base": Vector3(0, 0, 0.45), "tail_tip": Vector3(0, 0.1, 1),
}
const SKELETON := [["nose", "eye_l"], ["nose", "eye_r"], ["nose", "dorsal"], ["dorsal", "tail_base"],
	["nose", "fin_l"], ["nose", "fin_r"], ["fin_l", "tail_base"], ["fin_r", "tail_base"], ["tail_base", "tail_tip"]]

var style := Style.EARNEST:
	set(value):
		style = value
		if _overlay:
			_overlay.queue_redraw()

var fish: Fish
var cards: CardSystem
var camera: Camera3D

## Detector state, updated every frame (read by the overlay and tests).
var box := Rect2()
var detected := false
var confidence := 0.97
var occluded := false
var fps := 31.4
var trail: Array[Vector2] = [] ## screen positions, oldest first
var heat := PackedFloat32Array()
var log_lines: PackedStringArray = []
## Keypoint name -> screen position.
var keypoints := {}
## Where the fish will be in half a second, if it keeps going (screen space).
var predicted: Array[Vector2] = []
var latency_ms := 12.0
var track_id := 1
## Seconds left of an over-the-top "recalibrating" flicker.
var recalibrating := 0.0

var _trail_times: Array[float] = []
var _time := 0.0
var _noise := FastNoiseLite.new()
var _overlay: Control
var _font: Font
var _last_held := PackedStringArray()
var _raw_box := Rect2()


func _init() -> void:
	title = TITLE
	size = SIZE
	min_size = Vector2i(640, 360)
	visible = false # force_native can only change while hidden
	# A real OS window where the platform supports several; embedded otherwise
	# (headless runs and tests).
	force_native = DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS)
	content_scale_size = SIZE
	content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	heat.resize(HEAT_CELLS.x * HEAT_CELLS.y)
	_noise.seed = 7
	_noise.frequency = 0.8


func _ready() -> void:
	close_requested.connect(hide)
	_font = UiStyle.font(500, true)
	_overlay = Overlay.new()
	_overlay.cam = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


## Mirrors `source` (the room camera) with a camera of our own: a camera
## belongs to the viewport it's in, and this window is its own viewport.
func follow(source: Camera3D) -> void:
	camera = Camera3D.new()
	camera.fov = source.fov
	camera.near = source.near
	add_child(camera)
	camera.global_transform = source.global_transform
	camera.make_current()


func _process(delta: float) -> void:
	if fish == null or camera == null or not visible:
		return
	_time += delta
	_detect()
	_update_trail()
	_update_heat()
	_update_log()
	fps = clampf(fps + randf_range(-0.6, 0.6), 27.5, 33.8)
	latency_ms = clampf(latency_ms + randf_range(-0.4, 0.4), 9.5, 16.0)
	recalibrating = maxf(recalibrating - delta, 0.0)
	if style == Style.OVER_THE_TOP and recalibrating <= 0.0 and randf() < delta / 25.0:
		recalibrating = 0.6
		_log("confidence drift: recalibrating")
	_overlay.queue_redraw()


## Where the fish is in the picture, and how sure "the model" is about it.
func _detect() -> void:
	var xf := fish.global_transform
	var bounds := _fish_bounds()
	var rect := Rect2()
	var first := true
	for i in 8:
		var world := xf * bounds.get_endpoint(i)
		if camera.is_position_behind(world):
			continue
		var p := camera.unproject_position(world)
		rect = Rect2(p, Vector2.ZERO) if first else rect.expand(p)
		first = false
	# Pad a little, as detectors do, and smooth with a touch of jitter: real
	# boxes wobble a few pixels frame to frame.
	var was := detected
	_raw_box = rect.grow(6.0)
	detected = not first and Rect2(Vector2.ZERO, Vector2(SIZE)).intersects(_raw_box)
	if detected and not was:
		track_id += 1
	var wobble := Vector2(_noise.get_noise_2d(_time * 9.0, 1.0), _noise.get_noise_2d(_time * 9.0, 5.0)) * 3.0
	if not was or box.size == Vector2.ZERO:
		box = _raw_box
	else:
		box = Rect2(box.position.lerp(_raw_box.position + wobble, 0.35), box.size.lerp(_raw_box.size, 0.35))
	_keypoints(xf, bounds)
	_predict()
	occluded = _is_occluded()
	var jitter := _noise.get_noise_1d(_time) * 0.02
	var target := 0.41 if occluded else 0.965
	confidence = clampf(lerpf(confidence, target, 0.15) + jitter, 0.05, 0.995)


func _keypoints(xf: Transform3D, bounds: AABB) -> void:
	keypoints.clear()
	var c := bounds.get_center()
	var h := bounds.size / 2.0
	for key: String in KEYPOINTS:
		var f: Vector3 = KEYPOINTS[key]
		var world := xf * (c + f * h)
		if not camera.is_position_behind(world):
			var jitter := Vector2(_noise.get_noise_2d(_time * 6.0, key.hash() % 97), _noise.get_noise_2d(key.hash() % 89, _time * 6.0)) * 2.0
			keypoints[key] = camera.unproject_position(world) + jitter


func _predict() -> void:
	predicted.clear()
	if not detected:
		return
	var p := fish.global_position
	var v := fish.velocity
	for i in range(1, 7):
		var world := p + v * (i * 0.08)
		if not camera.is_position_behind(world):
			predicted.append(camera.unproject_position(world))


## The fish model's bounds in its own space.
func _fish_bounds() -> AABB:
	for child in fish.get_children():
		if child is FishModel:
			return child.local_aabb()
	return AABB(Vector3(-0.018, -0.024, -0.045), Vector3(0.036, 0.048, 0.09))


func _is_occluded() -> bool:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, fish.global_position, 2)
	return not camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _update_trail() -> void:
	if not detected:
		return
	trail.append(box.get_center())
	_trail_times.append(_time)
	while not _trail_times.is_empty() and _time - _trail_times[0] > TRAIL_SECONDS:
		_trail_times.pop_front()
		trail.pop_front()


func _update_heat() -> void:
	for i in heat.size():
		heat[i] *= 0.997
	if not detected:
		return
	var c := box.get_center() / Vector2(SIZE) * Vector2(HEAT_CELLS)
	var cell := Vector2i(clampi(int(c.x), 0, HEAT_CELLS.x - 1), clampi(int(c.y), 0, HEAT_CELLS.y - 1))
	var i := cell.y * HEAT_CELLS.x + cell.x
	heat[i] = minf(heat[i] + 0.04, 1.0)


func _update_log() -> void:
	var held := cards.held() if cards else PackedStringArray()
	if held != _last_held:
		for id in held:
			if id not in _last_held:
				_log("ACTION  %s ↦ host  (p=%.2f)" % [CardSystem.short_name(id), confidence])
		_last_held = held.duplicate()
	if style == Style.OVER_THE_TOP and randf() < 0.012:
		_log(["re-weighting attention heads", "target re-acquired", "fin pose estimate ok",
			"optical flow stable", "reticulating scales", "kalman gain nominal",
			"bubble artefact rejected", "zone prior updated"].pick_random())


func _log(line: String) -> void:
	log_lines.append("[%06.2f] %s" % [_time, line])
	while log_lines.size() > 12:
		log_lines.remove_at(0)


## The input names the fish is currently pressing.
func held_text() -> String:
	var held := cards.held() if cards else PackedStringArray()
	if held.is_empty():
		return "idle"
	var names := PackedStringArray()
	for id in held:
		names.append(CardSystem.short_name(id))
	return " + ".join(names)


## Names of the cards the fish is in front of, or whose sequence is playing.
func zone_text() -> String:
	if cards == null:
		return "-"
	var names := PackedStringArray()
	for card in cards.engaged_cards():
		names.append("[%s]" % card.binding.display_name())
	return " ".join(names) if not names.is_empty() else "open water"


## A made-up "intent" from how the fish is moving, for the over-the-top style.
func intent() -> Array:
	var v := fish.velocity
	if fish.dart_timer > fish.dart_cooldown - 0.3:
		return ["BURST", 0.93]
	if v.length() < 0.03:
		return ["LOITER", 0.71 + _noise.get_noise_1d(_time * 3.0) * 0.1]
	if absf(v.y) > 0.08:
		return ["ASCEND" if v.y > 0.0 else "DESCEND", 0.64]
	return ["PATROL", 0.58 + absf(_noise.get_noise_1d(_time * 2.0)) * 0.3]


class Overlay:
	extends Control
	var cam: TrackingCam

	const GREEN := Color(0.22, 0.88, 0.54)
	const AMBER := Color(1.0, 0.72, 0.2)
	const CYAN := Color(0.4, 0.85, 1.0)
	const INK := Color(0.9, 0.97, 1.0)
	const SHADE := Color(0, 0, 0, 0.55)

	func _draw() -> void:
		if cam == null or cam.fish == null:
			return
		match cam.style:
			TrackingCam.Style.MINIMAL:
				_draw_box(false)
				_panel_text(Vector2(24, 40), "held: %s" % cam.held_text(), 20, INK)
			TrackingCam.Style.EARNEST:
				_draw_earnest()
			TrackingCam.Style.OVER_THE_TOP:
				_draw_earnest()
				_draw_over_the_top()

	func _draw_earnest() -> void:
		_draw_heat()
		_draw_trail()
		_draw_zones()
		_draw_box(true)
		_draw_skeleton()
		_panel_text(Vector2(24, 40), "%s  ·  %.1f fps  ·  %.1f ms" % [TrackingCam.MODEL, cam.fps, cam.latency_ms], 18, INK)
		var status := "TRACKING" if cam.detected else "SEARCHING"
		if cam.detected and cam.occluded:
			status = "OCCLUDED"
		_panel_text(Vector2(24, 70), "%s  ·  %d obj  ·  nms 0.45  ·  %s" % [status, 1 if cam.detected else 0, _clock()], 14, INK.darkened(0.2))
		var bottom := size.y - 30
		_panel_text(Vector2(24, bottom - 32), "zone: %s" % cam.zone_text(), 18, AMBER)
		_panel_text(Vector2(24, bottom), "held: %s" % cam.held_text(), 20, GREEN if cam.held_text() != "idle" else INK)
		# The last few detections, bottom right.
		if cam.style == TrackingCam.Style.EARNEST:
			var lines := cam.log_lines.slice(maxi(cam.log_lines.size() - 4, 0))
			var y := size.y - 24 - (lines.size() - 1) * 17
			if not lines.is_empty():
				draw_rect(Rect2(size.x - 440, y - 16, 420, lines.size() * 17 + 8), SHADE)
			for line in lines:
				_text(Vector2(size.x - 432, y), line, 12, Color(GREEN, 0.9))
				y += 17
		# REC dot, top right.
		if fmod(cam._time, 1.2) < 0.8:
			draw_circle(Vector2(size.x - 40, 34), 8, Color(1, 0.2, 0.2))
		_text(Vector2(size.x - 104, 40), "REC", 16, INK)

	## Corner brackets rather than a full rectangle, with a class tag.
	func _draw_box(with_details: bool) -> void:
		if not cam.detected:
			return
		var color := AMBER if cam.occluded else GREEN
		var r := cam.box
		var t := minf(18.0, minf(r.size.x, r.size.y) * 0.35)
		for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var sx := 1.0 if corner.x == r.position.x else -1.0
			var sy := 1.0 if corner.y == r.position.y else -1.0
			draw_line(corner, corner + Vector2(t * sx, 0), color, 3.0)
			draw_line(corner, corner + Vector2(0, t * sy), color, 3.0)
		draw_rect(r, Color(color, 0.25), false, 1.0)
		var label := "%s %.2f" % [TrackingCam.CLASS_NAME, cam.confidence]
		if with_details:
			label += "  #%d" % cam.track_id
		var font_size := 14
		var w := cam._font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 12
		var tag := Rect2(r.position + Vector2(0, -22), Vector2(w, 20))
		draw_rect(tag, color)
		draw_string(cam._font, tag.position + Vector2(6, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.02, 0.1, 0.05))

	func _draw_skeleton() -> void:
		if not cam.detected or cam.occluded:
			return
		for bone: Array in TrackingCam.SKELETON:
			if cam.keypoints.has(bone[0]) and cam.keypoints.has(bone[1]):
				draw_line(cam.keypoints[bone[0]], cam.keypoints[bone[1]], Color(CYAN, 0.7), 1.5, true)
		for key: String in cam.keypoints:
			draw_circle(cam.keypoints[key], 3.0, CYAN)
			draw_arc(cam.keypoints[key], 5.0, 0, TAU, 12, Color(CYAN, 0.5), 1.0, true)

	## The engaged cards' hit zones, outlined where the camera sees them.
	func _draw_zones() -> void:
		if cam.cards == null:
			return
		for card in cam.cards.engaged_cards():
			var pts := PackedVector2Array()
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var world := card.global_transform * Vector3(corner.x * card.size.x / 2, corner.y * card.size.y / 2, 0)
				if cam.camera.is_position_behind(world):
					return
				pts.append(cam.camera.unproject_position(world))
			pts.append(pts[0])
			for i in 4:
				_dashed(pts[i], pts[i + 1], AMBER)
			var label := "zone %s %.2f" % [card.binding.display_name(), clampf(cam.confidence - 0.03, 0.0, 1.0)]
			_text(pts[3] + Vector2(2, 14), label, 12, AMBER)

	func _dashed(a: Vector2, b: Vector2, color: Color) -> void:
		var length := a.distance_to(b)
		var n := int(length / 8.0)
		for i in n:
			if i % 2 == 0:
				draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), color, 1.5)

	func _draw_trail() -> void:
		var n := cam.trail.size()
		for i in range(1, n):
			var a := float(i) / n
			draw_line(cam.trail[i - 1], cam.trail[i], Color(GREEN, a * 0.8), 2.0)

	func _draw_heat() -> void:
		var cell := size / Vector2(TrackingCam.HEAT_CELLS)
		for y in TrackingCam.HEAT_CELLS.y:
			for x in TrackingCam.HEAT_CELLS.x:
				var h := cam.heat[y * TrackingCam.HEAT_CELLS.x + x]
				if h < 0.02:
					continue
				var c := Color(1.0, 0.25, 0.1).lerp(Color(1.0, 0.9, 0.2), h)
				draw_rect(Rect2(Vector2(x, y) * cell, cell), Color(c, minf(h, 1.0) * 0.35))

	func _draw_over_the_top() -> void:
		# Banner, top centre.
		var banner := TrackingCam.MODEL_XL
		var bw := cam._font.get_string_size(banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_panel_text(Vector2((size.x - bw) / 2, 40), banner, 16, CYAN)
		# Where the fish is headed.
		var n := cam.predicted.size()
		for i in n:
			draw_circle(cam.predicted[i], 4.0 - i * 0.4, Color(AMBER, 0.9 - i * 0.12))
		if n > 0 and cam.detected:
			_text(cam.predicted[n - 1] + Vector2(8, -6), "t+0.5s", 12, AMBER)
		# Fake activations: bars that twitch with the fish's movement.
		var origin := Vector2(size.x - 250, 90)
		_text(origin + Vector2(0, -8), "layer 7 activations", 13, INK.darkened(0.2))
		for i in 16:
			var v := absf(sin(cam._time * (1.3 + i * 0.37) + i) * 0.6 + cam.fish.effort * 0.5 + randf() * 0.1)
			draw_rect(Rect2(origin + Vector2(i * 14, 60 - v * 60), Vector2(10, v * 60)), Color(CYAN, 0.8))
		var intent: Array = cam.intent()
		_panel_text(Vector2(size.x - 250, 200), "INTENT  %s  %.2f" % [intent[0], intent[1]], 16, AMBER)
		# Scrolling log, on its own shaded panel so it reads over the cards.
		var y := size.y - 250
		if not cam.log_lines.is_empty():
			draw_rect(Rect2(size.x - 480, y - 16, 460, cam.log_lines.size() * 17 + 10), SHADE)
		for line in cam.log_lines:
			_text(Vector2(size.x - 470, y), line, 12, Color(GREEN, 0.9))
			y += 17
		# Scanlines, the odd glitch, and now and then a recalibration.
		for sy in range(0, int(size.y), 3):
			draw_line(Vector2(0, sy), Vector2(size.x, sy), Color(0, 0, 0, 0.12), 1.0)
		if randf() < 0.05:
			var gy := randf() * size.y
			draw_rect(Rect2(0, gy, size.x, randf_range(2, 8)), Color(0.5, 1.0, 0.8, 0.15))
		if cam.recalibrating > 0.0 and fmod(cam._time, 0.2) < 0.12:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 1.0, 0.8, 0.06))
			var msg := "RECALIBRATING…"
			var mw := cam._font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			_panel_text(Vector2((size.x - mw) / 2, size.y / 2), msg, 30, CYAN)

	func _clock() -> String:
		var t := Time.get_datetime_dict_from_system()
		return "%02d:%02d:%02d" % [t.hour, t.minute, t.second]

	func _panel_text(pos: Vector2, text: String, font_size: int, color: Color) -> void:
		var w := cam._font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_rect(Rect2(pos + Vector2(-8, -font_size - 4), Vector2(w + 16, font_size + 12)), SHADE)
		_text(pos, text, font_size, color)

	func _text(pos: Vector2, text: String, font_size: int, color: Color) -> void:
		draw_string(cam._font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
