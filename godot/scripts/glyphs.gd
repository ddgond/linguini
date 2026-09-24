extends Node
## Button glyphs (autoload "Glyphs"): how inputs are named and drawn on the
## cards, the monitor and the editor, in the style of the controller you hold.
## Only the art changes: the host always gets the same (Xbox-layout) inputs.
##
## The setting is "auto" until the player picks a set on the monitor: auto
## follows the last controller used, by its name (keyboard players see Xbox).

signal changed(set_name: String)

const SETS := ["xbox", "playstation", "nintendo"]
const SET_LABELS := ["Xbox", "PlayStation", "Nintendo"]

## Face buttons by position. Nintendo swaps the letters (bottom is B).
const FACE := {
	"xbox": {"A": ["A", Color(0.3, 0.72, 0.32)], "B": ["B", Color(0.87, 0.26, 0.22)],
		"X": ["X", Color(0.22, 0.47, 0.92)], "Y": ["Y", Color(0.96, 0.76, 0.14)]},
	"playstation": {"A": ["✕", Color(0.47, 0.62, 1.0)], "B": ["○", Color(1.0, 0.38, 0.42)],
		"X": ["□", Color(0.96, 0.52, 0.82)], "Y": ["△", Color(0.3, 0.84, 0.7)]},
	"nintendo": {"A": ["B", Color(0.55, 0.56, 0.6)], "B": ["A", Color(0.55, 0.56, 0.6)],
		"X": ["Y", Color(0.55, 0.56, 0.6)], "Y": ["X", Color(0.55, 0.56, 0.6)]},
}
const OTHER := {
	"xbox": {"LB": "LB", "RB": "RB", "LT": "LT", "RT": "RT", "START": "MENU", "BACK": "VIEW", "L3": "LS", "R3": "RS"},
	"playstation": {"LB": "L1", "RB": "R1", "LT": "L2", "RT": "R2", "START": "OPTIONS", "BACK": "CREATE", "L3": "L3", "R3": "R3"},
	"nintendo": {"LB": "L", "RB": "R", "LT": "ZL", "RT": "ZR", "START": "+", "BACK": "−", "L3": "LS", "R3": "RS"},
}

## "auto" or one of SETS, as stored in settings.
var setting := "auto"
## The set in use.
var current := "xbox"
var _detected := "xbox"


func _ready() -> void:
	setting = Settings.get_value("controls", "glyphs", "auto")
	for device in Input.get_connected_joypads():
		_detected = detect(Input.get_joy_name(device))
	current = _resolve()
	Input.joy_connection_changed.connect(func(device: int, connected: bool) -> void:
		if connected:
			_use_device(device))


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_use_device(event.device)


## Which set a controller's name suggests.
static func detect(joy_name: String) -> String:
	var n := joy_name.to_lower()
	for word in ["playstation", "dualsense", "dualshock", "ps3", "ps4", "ps5", "sony"]:
		if n.contains(word):
			return "playstation"
	for word in ["nintendo", "switch", "joy-con", "pro controller"]:
		if n.contains(word):
			return "nintendo"
	return "xbox"


## The set the last controller used suggests (what "auto" picks).
func detected() -> String:
	return _detected


func set_setting(value: String, remember := true) -> void:
	setting = value if value in SETS else "auto"
	if remember:
		Settings.set_value("controls", "glyphs", setting)
	_update()


func _use_device(device: int) -> void:
	var found := detect(Input.get_joy_name(device))
	if found != _detected:
		_detected = found
		_update()


func _update() -> void:
	var resolved := _resolve()
	if resolved != current:
		current = resolved
		changed.emit(current)


func _resolve() -> String:
	return setting if setting in SETS else _detected


## The printed name of an input: "A", "✕", "L1", "ZR", "OPTIONS"...
func label(id: String, set_name := "") -> String:
	var s := set_name if set_name != "" else current
	if FACE[s].has(id):
		return FACE[s][id][0]
	return OTHER[s].get(id, CardSystem.INPUTS.get(id, {}).get("label", id))


## A face button's colour in this set; other inputs keep the card colours.
func color(id: String, set_name := "") -> Color:
	var s := set_name if set_name != "" else current
	if FACE[s].has(id):
		return FACE[s][id][1]
	return CardSystem.INPUTS.get(id, {}).get("color", Color.GRAY)


## Draws a face-button glyph as a badge: a coloured disc with its letter or
## (PlayStation) its shape. `r` is the badge radius in pixels.
func draw_badge(ci: CanvasItem, id: String, center: Vector2, r: float, set_name := "") -> void:
	var s := set_name if set_name != "" else current
	var c := color(id, s)
	if s == "playstation":
		ci.draw_circle(center, r, Color(0.12, 0.12, 0.15))
		_draw_ps_shape(ci, id, center, r * 0.5, c, r * 0.16)
		return
	ci.draw_circle(center, r, c)
	ci.draw_circle(center, r * 0.86, c.lightened(0.08))
	var text := label(id, s)
	var font := UiStyle.font(800)
	var size := int(r * 1.25)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	ci.draw_string(font, center + Vector2(-w.x / 2, size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)


func _draw_ps_shape(ci: CanvasItem, id: String, c: Vector2, r: float, col: Color, w: float) -> void:
	match id:
		"A":
			ci.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, w, true)
			ci.draw_line(c + Vector2(-r, r), c + Vector2(r, -r), col, w, true)
		"B":
			ci.draw_arc(c, r, 0, TAU, 40, col, w, true)
		"X":
			ci.draw_rect(Rect2(c - Vector2(r, r) * 0.9, Vector2(r, r) * 1.8), col, false, w, true)
		"Y":
			var pts := PackedVector2Array([c + Vector2(0, -r * 1.05), c + Vector2(r, r * 0.7), c + Vector2(-r, r * 0.7), c + Vector2(0, -r * 1.05)])
			ci.draw_polyline(pts, col, w, true)


## Draws a shoulder, trigger, stick-click or menu button as a rounded pill
## with its name. `h` is the pill's height in pixels.
func draw_pill(ci: CanvasItem, id: String, center: Vector2, h: float, fill: Color, set_name := "") -> void:
	var text := label(id, set_name)
	var font := UiStyle.font(800)
	var size := int(h * 0.55)
	var w := maxf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + h * 0.7, h * 1.4)
	var rect := Rect2(center - Vector2(w, h) / 2, Vector2(w, h))
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(h / 2) if id in ["LB", "RB", "L3", "R3"] else int(h * 0.28))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, rect)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font, center + Vector2(-tw / 2, size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)


## Draws a direction (D-pad or stick): a chunky arrow, `r` its half-length.
static func draw_arrow(ci: CanvasItem, dir: Vector2, center: Vector2, r: float, col: Color) -> void:
	# `dir` is y-up; the canvas is y-down.
	var d := Vector2(dir.x, -dir.y).normalized()
	var side := Vector2(-d.y, d.x)
	var tip := center + d * r
	var neck := center + d * r * 0.1
	var tail := center - d * r
	var shaft := r * 0.3
	var head := r * 0.72
	ci.draw_colored_polygon(PackedVector2Array([
		tail + side * shaft, neck + side * shaft, neck + side * head, tip,
		neck - side * head, neck - side * shaft, tail - side * shaft]), col)
