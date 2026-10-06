class_name DirectInput
extends CanvasLayer
## Direct input mode (Direct input on the in-stream menu): the keyboard and
## mouse go straight to the host, as in a plain Moonlight client, for
## debugging or just using the PC, while the fish and cards rest. The stream
## shows on the room's monitor (main.gd frames it, the menu put away); F11
## fills the window with it instead, and back.
##
## Ctrl+Alt+Shift+Q (Moonlight's own) or holding Start and Back on a gamepad
## for a second leaves it. Keys are sent by where they are on the keyboard
## (Windows virtual-key codes of a US layout), so the host's own layout
## applies. Keys still held are released on the host when the mode ends.

signal exit_requested

const EXIT_HOLD := 1.0

var client: Object
var active := false:
	set = set_active
## The stream filling the window, rather than on the room's monitor.
var fullscreen := false:
	set = set_fullscreen

var _view: ColorRect
var _material: ShaderMaterial
var _hint: Label
var _hint_time := 0.0
var _held := {}  ## virtual-key codes held down on the host
var _pad_hold := 0.0


func _ready() -> void:
	layer = 50
	visible = false
	_view = ColorRect.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/direct_view.gdshader")
	_view.material = _material
	_view.visible = false
	add_child(_view)
	if client:
		_material.set_shader_parameter("y_tex", client.get_y_texture())
		_material.set_shader_parameter("uv_tex", client.get_uv_texture())
	_hint = Label.new()
	_hint.text = "Direct input: keyboard and mouse go to the host.  F11: full screen.  Ctrl+Alt+Shift+Q, or hold %s + %s on a gamepad, to leave." % [
		Glyphs.label("START"), Glyphs.label("BACK")]
	_hint.add_theme_font_override("font", UiStyle.font(700))
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color.WHITE)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 8)
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_top = 24
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)


func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	visible = active
	if not active:
		_release_all()
		fullscreen = false
	_hint_time = 6.0
	_pad_hold = 0.0
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	if _view:
		_view.visible = fullscreen
	# Full screen covers the room: don't draw it underneath.
	if is_inside_tree():
		get_viewport().disable_3d = fullscreen and active


func _process(delta: float) -> void:
	if not active:
		return
	if client:
		var video: bool = client.has_video()
		_material.set_shader_parameter("has_video", video)
		if video:
			_material.set_shader_parameter("video_size", Vector2(client.get_video_size()))
			_material.set_shader_parameter("bt709", client.is_bt709())
			_material.set_shader_parameter("full_range", client.is_full_range())
	_material.set_shader_parameter("view_size", _view.size)
	_hint_time = maxf(_hint_time - delta, 0.0)
	_hint.modulate.a = clampf(_hint_time, 0.0, 1.0)
	# Start and Back held together on any gamepad: leave.
	var both := false
	for device in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, JOY_BUTTON_START) and Input.is_joy_button_pressed(device, JOY_BUTTON_BACK):
			both = true
	_pad_hold = _pad_hold + delta if both else 0.0
	if _pad_hold >= EXIT_HOLD:
		_pad_hold = 0.0
		exit_requested.emit()


func _input(event: InputEvent) -> void:
	if not active:
		return
	get_viewport().set_input_as_handled()  # nothing else sees it meanwhile
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.physical_keycode == KEY_Q and k.ctrl_pressed and k.alt_pressed and k.shift_pressed:
			exit_requested.emit()
			return
		if k.physical_keycode == KEY_F11:
			if k.pressed and not k.echo:
				fullscreen = not fullscreen
				_hint_time = 3.0
			return
		var vk := virtual_key(k)
		if vk == 0 or (k.echo and k.pressed):
			return
		if k.pressed:
			_held[vk] = true
		else:
			_held.erase(vk)
		_send_key(vk, k.pressed, modifiers(k))
	elif event is InputEventMouseMotion:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		if client:
			client.send_mouse_move(roundi(rel.x), roundi(rel.y))
	elif event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		match b.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if b.pressed and client:
					client.send_scroll(120 if b.button_index == MOUSE_BUTTON_WHEEL_UP else -120)
			_:
				var button: int = {MOUSE_BUTTON_LEFT: 1, MOUSE_BUTTON_MIDDLE: 2, MOUSE_BUTTON_RIGHT: 3,
					MOUSE_BUTTON_XBUTTON1: 4, MOUSE_BUTTON_XBUTTON2: 5}.get(b.button_index, 0)
				if button and client:
					client.send_mouse_button(button, b.pressed)


func _send_key(vk: int, pressed: bool, mods: int) -> void:
	if client:
		client.send_keyboard(vk, pressed, mods)


func _release_all() -> void:
	for vk: int in _held.keys():
		_send_key(vk, false, 0)
	_held.clear()


## Moonlight's modifier bits for a key event.
static func modifiers(k: InputEventKey) -> int:
	return (1 if k.shift_pressed else 0) | (2 if k.ctrl_pressed else 0) | (4 if k.alt_pressed else 0) | (8 if k.meta_pressed else 0)


## The Windows virtual-key code for where the key is on the keyboard, or 0.
static func virtual_key(k: InputEventKey) -> int:
	var code := k.physical_keycode
	if code >= KEY_A and code <= KEY_Z:
		return code  # 'A'..'Z' are their own codes
	if code >= KEY_0 and code <= KEY_9:
		return code
	if code >= KEY_F1 and code <= KEY_F24:
		return 0x70 + (code - KEY_F1)
	if code >= KEY_KP_0 and code <= KEY_KP_9:
		return 0x60 + (code - KEY_KP_0)
	var right := k.location == KEY_LOCATION_RIGHT
	match code:
		KEY_SHIFT:
			return 0xA1 if right else 0xA0
		KEY_CTRL:
			return 0xA3 if right else 0xA2
		KEY_ALT:
			return 0xA5 if right else 0xA4
		KEY_META:
			return 0x5C if right else 0x5B
	return VK.get(code, 0)


const VK := {
	KEY_ESCAPE: 0x1B, KEY_TAB: 0x09, KEY_BACKSPACE: 0x08, KEY_ENTER: 0x0D, KEY_KP_ENTER: 0x0D, KEY_SPACE: 0x20,
	KEY_INSERT: 0x2D, KEY_DELETE: 0x2E, KEY_HOME: 0x24, KEY_END: 0x23, KEY_PAGEUP: 0x21, KEY_PAGEDOWN: 0x22,
	KEY_LEFT: 0x25, KEY_UP: 0x26, KEY_RIGHT: 0x27, KEY_DOWN: 0x28,
	KEY_CAPSLOCK: 0x14, KEY_NUMLOCK: 0x90, KEY_SCROLLLOCK: 0x91, KEY_PRINT: 0x2C, KEY_PAUSE: 0x13, KEY_MENU: 0x5D,
	KEY_SEMICOLON: 0xBA, KEY_EQUAL: 0xBB, KEY_COMMA: 0xBC, KEY_MINUS: 0xBD, KEY_PERIOD: 0xBE, KEY_SLASH: 0xBF,
	KEY_QUOTELEFT: 0xC0, KEY_BRACKETLEFT: 0xDB, KEY_BACKSLASH: 0xDC, KEY_BRACKETRIGHT: 0xDD, KEY_APOSTROPHE: 0xDE,
	KEY_KP_MULTIPLY: 0x6A, KEY_KP_ADD: 0x6B, KEY_KP_SUBTRACT: 0x6D, KEY_KP_PERIOD: 0x6E, KEY_KP_DIVIDE: 0x6F,
}
