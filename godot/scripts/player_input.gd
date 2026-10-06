class_name PlayerInput
extends RefCounted
## One local player's controls: the keyboard and mouse, one gamepad, or both
## (player 1 by default plays with the keyboard and the first pad they use).
## Fish and FishCamera read it instead of the global input actions, so in
## co-op each fish answers only to its own player.
##
## The keyboard side reads the kb_* actions (keys and mouse buttons only,
## from InputSetup); a pad is read directly by its device id, with the same
## layout as the global actions: left stick swims, right stick looks, RB / LB
## rise and sink, A darts, LT gazes at the monitor, Start opens the menu and
## Back held leaves (players 2 and up).

const DEADZONE := 0.2
const TRIGGER_DOWN := 0.5

## Whether the keyboard and mouse drive this player.
var keyboard := false
## The gamepad's device id, or -1 for none.
var pad := -1

var _dart_was := false


func _init(p_keyboard := false, p_pad := -1) -> void:
	keyboard = p_keyboard
	pad = p_pad


## Swim stick: x right, y forward, each -1..1.
func stick() -> Vector2:
	var v := Vector2.ZERO
	if keyboard:
		v = Input.get_vector("kb_fish_left", "kb_fish_right", "kb_fish_back", "kb_fish_forward")
	if pad >= 0:
		var p := _axes(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
		if p.length() > v.length():
			v = Vector2(p.x, -p.y)
	return v


## Rise (+1) or sink (-1).
func vertical() -> float:
	var v := 0.0
	if keyboard:
		v = Input.get_axis("kb_fish_sink", "kb_fish_rise")
	if pad >= 0:
		v += float(Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_SHOULDER)) - float(Input.is_joy_button_pressed(pad, JOY_BUTTON_LEFT_SHOULDER))
	return clampf(v, -1.0, 1.0)


## True once per press of dart.
func dart_pressed() -> bool:
	var down := false
	if keyboard:
		down = Input.is_action_pressed("kb_fish_dart")
	if pad >= 0:
		down = down or Input.is_joy_button_pressed(pad, JOY_BUTTON_A)
	var pressed := down and not _dart_was
	_dart_was = down
	return pressed


## Right stick look: x right, y up, each -1..1 (the mouse is handled by
## FishCamera's input events).
func look() -> Vector2:
	if pad < 0:
		return Vector2.ZERO
	var p := _axes(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	return Vector2(p.x, -p.y)


## Holding the gaze (watch the monitor) control.
func gazing() -> bool:
	var g := false
	if keyboard:
		g = Input.is_action_pressed("kb_gaze")
	if pad >= 0:
		g = g or Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT) > TRIGGER_DOWN
	return g


## Holding Back on the pad (players 2 and up leave by holding it).
func back_held() -> bool:
	return pad >= 0 and Input.is_joy_button_pressed(pad, JOY_BUTTON_BACK)


## Whether an input event came from this player's devices.
func owns(event: InputEvent) -> bool:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return pad >= 0 and event.device == pad
	return keyboard and (event is InputEventKey or event is InputEventMouse)


func _axes(x_axis: JoyAxis, y_axis: JoyAxis) -> Vector2:
	var v := Vector2(Input.get_joy_axis(pad, x_axis), Input.get_joy_axis(pad, y_axis))
	if v.length() < DEADZONE:
		return Vector2.ZERO
	return v.normalized() * inverse_lerp(DEADZONE, 1.0, minf(v.length(), 1.0))
