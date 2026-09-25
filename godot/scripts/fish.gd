class_name Fish
extends CharacterBody3D
## Real Fishy Movement(TM).
##
## Player input is an *urge*: a direction the fish wants to go and how badly it
## wants to go there. It is never a velocity. The fish turns toward the urge at a
## limited rate and propels itself in tail-beat pulses, so quick changes of mind
## come out as arcs. Water drag is much stronger sideways than lengthways, which
## makes the velocity follow the heading the way a real fish's does.
##
## The player steers from the fish's point of view, not the camera's: forward
## swims along the fish's heading, back makes it back up, and left and right
## turn it.
##
## With no input the fish hovers: pectoral-fin sculling, a slow bob and a lazy
## wander that steers away from the glass.

signal darted

@export_group("Swimming")
@export var cruise_speed := 0.30 ## m/s at full effort
@export var turn_rate := 3.2 ## rad/s at full effort
@export var turn_response := 4.0 ## 1/s: turning slows as the heading nears the urge
@export var pitch_rate := 2.0 ## rad/s
@export var max_pitch := deg_to_rad(55.0)
@export var tail_freq_idle := 1.1 ## tail beats per second
@export var tail_freq_max := 5.0
@export var rise_accel := 0.25 ## m/s^2 of swim-bladder assist for rise/sink
@export var back_speed := 0.07 ## m/s when backing up on pectoral fins
@export var back_turn_rate := 1.2 ## rad/s when turning while backing up

@export_group("Water")
@export var forward_drag := 1.8 ## 1/s
@export var lateral_drag := 7.0 ## 1/s
@export var vertical_drag := 2.5 ## 1/s

@export_group("Dart")
@export var dart_speed := 0.75 ## m/s added instantly
@export var dart_cooldown := 0.8 ## s

@export_group("Idle")
@export var idle_effort := 0.05
@export var idle_wander := 0.35 ## rad/s
@export var idle_bob := 0.012 ## m/s

## Interior of the tank in global space, for idle wall avoidance.
var bounds := AABB()

# Urge, set by read_player_input() or drive().
var urge_dir := Vector3.ZERO
var urge_strength := 0.0
var vertical_urge := 0.0
var backing := false
var dart_requested := false

## When true, the fish reads the keyboard/gamepad each physics tick.
var player_control := false

# Body state, readable by the model and camera.
var yaw := 0.0
var pitch := 0.0
var roll := 0.0
var effort := 0.0
var yaw_rate := 0.0 ## rad/s, this physics tick
var tail_phase := 0.0
var fin_phase := 0.0
var dart_timer := 0.0

## For screenshots: when 0 or more, the fish holds its place but keeps
## swimming in place at this effort, turning at pose_turn rad/s.
var pose_effort := -1.0
var pose_turn := 0.0
## For screenshots: when set, the fish swims this way (tank space) at full
## effort instead of reading the player's input.
var autopilot := Vector3.ZERO

var _time := 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	add_to_group("fish")  # for things it pushes around (DecorBall)
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	_noise.seed = randi()
	_noise.frequency = 0.15
	yaw = rotation.y


func _physics_process(delta: float) -> void:
	if pose_effort >= 0.0:
		_hold_pose(delta)
		return
	if autopilot != Vector3.ZERO:
		drive(autopilot, 1.0)
	elif player_control:
		read_player_input()
	simulate(delta)
	move_and_slide()


## Sets the urge directly (tests, autopilot).
func drive(direction: Vector3, strength: float, vertical := 0.0, back := false) -> void:
	urge_dir = direction.normalized() if direction.length() > 0.001 else Vector3.ZERO
	urge_strength = clampf(strength, 0.0, 1.0)
	vertical_urge = clampf(vertical, -1.0, 1.0)
	backing = back


func request_dart() -> void:
	dart_requested = true


func forward() -> Vector3:
	return -global_transform.basis.z


func read_player_input() -> void:
	var stick := Input.get_vector("fish_left", "fish_right", "fish_back", "fish_forward")
	var vertical := Input.get_axis("fish_sink", "fish_rise")
	if Input.is_action_just_pressed("fish_dart"):
		request_dart()

	# Left/right points the urge off to that side of the fish's heading, by an
	# angle that makes it turn at turn_rate with the stick fully over.
	var heading := yaw - stick.x * turn_rate / turn_response
	var dir := Vector3(-sin(heading), 0.0, -cos(heading))
	if stick.y < -0.3:
		# Fish don't swim backwards: they back up slowly on their pectoral fins.
		drive(dir, 0.0, vertical, true)
		return
	# A fish can't turn on the spot, so turning alone swims it round gently.
	var thrust := maxf(stick.y, absf(stick.x) * 0.35)
	# Rising or sinking tilts the fish that way as it swims.
	drive(dir * thrust + Vector3.UP * vertical * 0.6, maxf(thrust, absf(vertical) * 0.6), vertical)


func simulate(delta: float) -> void:
	_time += delta
	dart_timer = maxf(dart_timer - delta, 0.0)

	yaw_rate = 0.0
	var effort_target := 0.0
	var swimming := urge_strength > 0.05 and not backing

	if swimming:
		var target_yaw := atan2(-urge_dir.x, -urge_dir.z)
		var horizontal := Vector2(urge_dir.x, urge_dir.z).length()
		var target_pitch := clampf(atan2(urge_dir.y, horizontal), -max_pitch, max_pitch)
		var turn := angle_difference(yaw, target_yaw)
		if horizontal < 0.2:
			turn = 0.0 # mostly vertical urge: keep heading, just pitch
		var max_step := turn_rate * (0.5 + 0.5 * urge_strength) * delta
		var step := clampf(turn * turn_response * delta, -max_step, max_step)
		yaw_rate = step / delta
		yaw = wrapf(yaw + step, -PI, PI)
		pitch = move_toward(pitch, target_pitch, pitch_rate * delta)
		# Fish ease off while turning hard: the tail is busy steering.
		effort_target = urge_strength * lerpf(1.0, 0.45, absf(turn) / PI)
	elif backing:
		# Backing up can still turn toward the urge, slowly.
		var turn := angle_difference(yaw, atan2(-urge_dir.x, -urge_dir.z)) if urge_dir != Vector3.ZERO else 0.0
		yaw_rate = clampf(turn * turn_response, -back_turn_rate, back_turn_rate)
		yaw = wrapf(yaw + yaw_rate * delta, -PI, PI)
		pitch = move_toward(pitch, 0.0, 0.6 * delta)
		effort_target = 0.0
	else:
		yaw_rate = _idle_steer()
		yaw = wrapf(yaw + yaw_rate * delta, -PI, PI)
		pitch = move_toward(pitch, 0.0, 0.6 * delta)
		effort_target = idle_effort

	effort = lerpf(effort, effort_target, 1.0 - exp(-4.0 * delta))

	# Tail beats: thrust arrives in pulses. sin^2 averages to 1/2, hence the 2.
	var freq := lerpf(tail_freq_idle, tail_freq_max, effort)
	tail_phase = fmod(tail_phase + TAU * freq * delta, TAU * 64.0)
	var pulse := 2.0 * pow(sin(tail_phase), 2.0)
	var fwd := _heading()
	velocity += fwd * effort * cruise_speed * forward_drag * pulse * delta

	fin_phase += TAU * (6.0 if backing else 2.0) * delta
	if backing:
		velocity += -fwd * back_speed * forward_drag * delta

	velocity.y += vertical_urge * rise_accel * delta
	if not swimming:
		# Hover: a slow bob around neutral buoyancy.
		velocity.y += (sin(_time * 0.9) * idle_bob - velocity.y) * 0.8 * delta

	if dart_requested and dart_timer <= 0.0:
		velocity += fwd * dart_speed
		dart_timer = dart_cooldown
		tail_phase += PI * 0.5
		darted.emit()
	dart_requested = false

	# Water drag, anisotropic: sideways motion dies quickly, so velocity follows
	# the heading and turns become arcs.
	var along := fwd * velocity.dot(fwd)
	var side := velocity - along
	side = Vector3(side.x, 0.0, side.z) * exp(-lateral_drag * delta) + Vector3(0.0, side.y, 0.0) * exp(-vertical_drag * delta)
	velocity = along * exp(-forward_drag * delta) + side

	# Bank into turns, and always right itself.
	var target_roll := clampf(-yaw_rate * 0.15, -0.5, 0.5)
	roll = lerpf(roll, target_roll, 1.0 - exp(-5.0 * delta))

	global_transform.basis = Basis.from_euler(Vector3(pitch, yaw, roll))


func _heading() -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD


## Idle yaw rate: a lazy wander, overridden by turning away from nearby glass.
func _idle_steer() -> float:
	var wander := _noise.get_noise_1d(_time) * idle_wander * 2.0
	if bounds.size == Vector3.ZERO:
		return wander
	var look := global_position + _heading() * 0.12
	var inner := bounds.grow(-0.06)
	if inner.has_point(Vector3(look.x, inner.get_center().y, look.z)):
		return wander
	var to_center := inner.get_center() - global_position
	var target := atan2(-to_center.x, -to_center.z)
	return clampf(angle_difference(yaw, target), -1.0, 1.0) * 0.8


func _hold_pose(delta: float) -> void:
	effort = pose_effort
	yaw_rate = pose_turn
	tail_phase = fmod(tail_phase + TAU * lerpf(tail_freq_idle, tail_freq_max, effort) * delta, TAU * 64.0)
	fin_phase += TAU * 2.0 * delta
