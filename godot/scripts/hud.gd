class_name Hud
extends CanvasLayer
## Minimal on-screen info while swimming: which cards are held and stream status.

const NAMES := {
	"DPAD_UP": "D-pad up", "DPAD_DOWN": "D-pad down", "DPAD_LEFT": "D-pad left", "DPAD_RIGHT": "D-pad right",
	"L_UP": "L-stick up", "L_DOWN": "L-stick down", "L_LEFT": "L-stick left", "L_RIGHT": "L-stick right",
	"R_UP": "R-stick up", "R_DOWN": "R-stick down", "R_LEFT": "R-stick left", "R_RIGHT": "R-stick right",
}

var client: Object

var _held: Label
var _status: Label


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	_status = _make_label(18, Color(0.85, 0.9, 1.0, 0.8))
	_status.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(_status)

	_held = _make_label(26, Color(1.0, 0.85, 0.4))
	_held.size_flags_vertical = Control.SIZE_SHRINK_END
	margin.add_child(_held)

	var hint := _make_label(16, Color(0.8, 0.85, 0.95, 0.6))
	hint.text = "Hold right mouse / LT to watch the monitor  ·  Esc / Start for the menu"
	hint.size_flags_vertical = Control.SIZE_SHRINK_END
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	margin.add_child(hint)


func set_held(inputs: PackedStringArray) -> void:
	var names := PackedStringArray()
	for id in inputs:
		names.append(NAMES.get(id, id))
	_held.text = "" if names.is_empty() else "Holding: " + ", ".join(names)


func _process(_delta: float) -> void:
	if client and client.is_streaming():
		var size: Vector2i = client.get_video_size()
		_status.text = "● LIVE  %dx%d  %.0f fps" % [size.x, size.y, client.get_video_fps()]
	else:
		_status.text = "Not streaming: cards light up but send nothing"


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
