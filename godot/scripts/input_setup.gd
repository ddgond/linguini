extends Node
## Registers Linguini's input actions at startup. Keeping them here (rather than as
## serialized InputEvents in project.godot) makes the bindings easy to read and edit.
##
## The player's own keyboard/gamepad only ever drives the fish and the menus; nothing
## here is forwarded to the host. Only the flash cards in the tank do that.

const STICK_DEADZONE := 0.2


func _enter_tree() -> void:
	_bind("fish_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("fish_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("fish_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("fish_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("fish_rise", [KEY_SPACE], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_bind("fish_sink", [KEY_C, KEY_CTRL], [JOY_BUTTON_LEFT_SHOULDER], [])
	_bind("fish_dart", [KEY_SHIFT], [JOY_BUTTON_A], [])
	_bind("camera_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_bind("camera_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_bind("camera_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_bind("camera_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_bind("gaze", [KEY_TAB], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_bind_mouse("gaze", MOUSE_BUTTON_RIGHT)
	_bind("menu_toggle", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	_bind("debug_zones", [KEY_F3], [], [])


func _bind(action: StringName, keys: Array, buttons: Array, axes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, STICK_DEADZONE)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for button in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		InputMap.action_add_event(action, ev)
	for axis in axes:
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis[0]
		ev.axis_value = axis[1]
		InputMap.action_add_event(action, ev)


func _bind_mouse(action: StringName, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
