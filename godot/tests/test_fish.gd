extends "res://tests/test_case.gd"
## Real Fishy Movement: checks the body model directly (simulate() with manual
## integration, no physics server).

const DT := 1.0 / 120.0


func _fish() -> Fish:
	var f := Fish.new()
	add(f)
	f.set_physics_process(false) # stepped by hand below
	f._noise.seed = 7
	return f


func _run(f: Fish, seconds: float, per_step := Callable()) -> Vector3:
	var pos := Vector3.ZERO
	var steps := int(seconds / DT)
	for i in steps:
		f.simulate(DT)
		pos += f.velocity * DT
		if per_step.is_valid():
			per_step.call(f)
	return pos


func test_idle_drifts_slowly() -> void:
	var f := _fish()
	var max_speed := [0.0]
	var travelled := _run(f, 10.0, func(x: Fish) -> void: max_speed[0] = maxf(max_speed[0], x.velocity.length()))
	check(max_speed[0] < 0.03, "idle fish should drift slowly, max speed %.3f" % max_speed[0])
	check(max_speed[0] > 0.001, "idle fish should not be perfectly still")
	check(travelled.length() < 0.25, "idle fish shouldn't go far in 10 s, went %.2f m" % travelled.length())
	check(absf(f.roll) < 0.05 and absf(f.pitch) < 0.05, "idle fish stays level")
	f.free()


func test_cruise_reaches_speed_in_pulses() -> void:
	var f := _fish()
	f.drive(Vector3.FORWARD, 1.0)
	_run(f, 3.0)
	var speeds: Array[float] = []
	_run(f, 2.0, func(x: Fish) -> void: speeds.append(x.velocity.length()))
	var avg: float = speeds.reduce(func(a: float, b: float) -> float: return a + b) / speeds.size()
	check(avg > f.cruise_speed * 0.7 and avg < f.cruise_speed * 1.25, "cruise speed %.3f vs %.3f" % [avg, f.cruise_speed])
	var spread: float = speeds.max() - speeds.min()
	check(spread > 0.01, "thrust should come in tail-beat pulses (speed spread %.4f)" % spread)
	f.free()


func test_turns_are_arcs() -> void:
	var f := _fish()
	f.drive(Vector3.FORWARD, 1.0)
	_run(f, 2.0)
	f.drive(Vector3.RIGHT, 1.0)
	_run(f, 0.1)
	check(absf(angle_difference(f.yaw, 0.0)) < 0.5, "fish must not snap to a new heading (turned %.2f rad in 0.1 s)" % absf(f.yaw))
	var path := _run(f, 2.0)
	check(absf(angle_difference(f.yaw, -PI / 2)) < 0.1, "fish ends up heading right, yaw %.2f" % f.yaw)
	# An arc keeps moving forward while turning; a snap turn would not.
	check(path.z < -0.05, "fish carries forward through the turn (dz %.3f)" % path.z)
	check(path.x > 0.1, "and ends up going right (dx %.3f)" % path.x)
	var fwd := Basis.from_euler(Vector3(f.pitch, f.yaw, 0)) * Vector3.FORWARD
	var lateral := (f.velocity - fwd * f.velocity.dot(fwd)).length()
	check(lateral < 0.02, "velocity follows the heading (lateral %.3f)" % lateral)
	f.free()


func test_dart_and_cooldown() -> void:
	var f := _fish()
	f.request_dart()
	f.simulate(DT)
	var burst := f.velocity.length()
	check(burst > 0.6, "dart gives a burst of speed (%.2f)" % burst)
	f.request_dart()
	f.simulate(DT)
	check(f.velocity.length() <= burst, "dart has a cooldown")
	_run(f, f.dart_cooldown)
	var before := f.velocity.length()
	f.request_dart()
	f.simulate(DT)
	check(f.velocity.length() > before + 0.5, "dart works again after the cooldown")
	f.free()


func test_backing_up() -> void:
	var f := _fish()
	f.drive(Vector3.ZERO, 0.0, 0.0, true)
	var path := _run(f, 3.0)
	check(path.z > 0.05, "fish backs up (dz %.3f)" % path.z)
	check(f.velocity.length() < f.back_speed * 1.3, "backing is slow (%.3f)" % f.velocity.length())
	check(absf(f.yaw) < 0.01, "backing doesn't turn the fish")
	f.free()


func test_rise_keeps_heading() -> void:
	var f := _fish()
	f.drive(Vector3.UP, 0.6, 1.0)
	var path := _run(f, 2.0)
	check(path.y > 0.1, "vertical urge makes the fish rise (dy %.3f)" % path.y)
	check(f.pitch > 0.3, "fish pitches nose-up to rise")
	check(absf(f.yaw) < 0.01, "rising doesn't change heading")
	f.free()


## Presses `actions` (fully) and steps the fish under player control.
func _run_input(f: Fish, actions: Array, seconds: float) -> Vector3:
	for a in actions:
		Input.action_press(a)
	var path := _run(f, seconds, func(x: Fish) -> void: x.read_player_input())
	for a in actions:
		Input.action_release(a)
	return path


func test_controls_are_fish_relative() -> void:
	var f := _fish()
	f.yaw = PI / 2 # facing -X
	var path := _run_input(f, ["fish_forward"], 2.0)
	check(path.x < -0.2 and absf(path.z) < 0.02, "forward swims along the fish's heading (%s)" % path)
	check(absf(angle_difference(f.yaw, PI / 2)) < 0.01, "forward alone doesn't turn the fish")

	var before := f.yaw
	_run_input(f, ["fish_right"], 0.25)
	var turned := angle_difference(before, f.yaw)
	check(turned < -0.2, "right turns the fish to its right (%.2f rad)" % turned)
	check(turned > -f.turn_rate * 0.25, "and no faster than turn_rate")

	f.yaw = PI / 2
	f.velocity = Vector3.ZERO
	path = _run_input(f, ["fish_back"], 3.0)
	check(f.backing and path.x > 0.05, "back backs up away from the heading (%s)" % path)
	before = f.yaw
	_run_input(f, ["fish_back", "fish_left"], 0.5)
	check(angle_difference(before, f.yaw) > 0.2, "left turns the fish while backing up")
	f.free()
