class_name FishCamera
extends Camera3D
## Third-person camera for the fish, with two other framings it blends into:
##
## - Gaze (hold right mouse / LT): swings round to look past the fish, through
##   the glass, at the monitor, zooming so the stream fills most of the view.
##   The fish keeps swimming.
## - Menu: a fixed spot inside the tank by the right-hand glass, framing the
##   monitor so its menus can be used.
##
## The camera stays inside the tank except through the front glass: the tank is
## only 50 cm deep and the cards face the front, so when the fish faces the cards
## the camera backs out through the glass and looks in, like the room camera.

const FOLLOW_FOV := 70.0
const MIN_PITCH := -1.2
const MAX_PITCH := 0.9

@export var distance := 0.26
@export var mouse_sensitivity := 0.004
@export var stick_speed := 2.5 ## rad/s
@export var recenter_delay := 1.2 ## s after the last manual look
@export var recenter_rate := 1.6
@export var gaze_time := 0.35 ## s to swing into / out of gaze
@export var front_leeway := 0.35 ## m the follow camera may back out through the front glass

var fish: Fish
var screen: Node3D
var screen_size := Vector2(0.8, 0.45)
## Tank interior in global space.
var bounds := AABB()
var menu_view := false

var orbit_yaw := 0.0
var orbit_pitch := -0.25
var gaze := 0.0 ## 0 = follow, 1 = gaze at monitor
var _menu := 0.0
var _manual_timer := 0.0
var _pivot := Vector3.ZERO


func _ready() -> void:
	fov = FOLLOW_FOV
	near = 0.01
	if fish:
		orbit_yaw = fish.yaw
		_pivot = fish.global_position


func _unhandled_input(event: InputEvent) -> void:
	if menu_view:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		orbit_yaw -= event.relative.x * mouse_sensitivity
		orbit_pitch = clampf(orbit_pitch - event.relative.y * mouse_sensitivity, MIN_PITCH, MAX_PITCH)
		_manual_timer = recenter_delay


func _process(delta: float) -> void:
	if fish == null:
		return

	var look := Input.get_vector("camera_left", "camera_right", "camera_down", "camera_up") if not menu_view else Vector2.ZERO
	if look != Vector2.ZERO:
		orbit_yaw -= look.x * stick_speed * delta
		orbit_pitch = clampf(orbit_pitch + look.y * stick_speed * delta, MIN_PITCH, MAX_PITCH)
		_manual_timer = recenter_delay
	_manual_timer = maxf(_manual_timer - delta, 0.0)

	# Drift back behind the fish once it's swimming and the player has let go.
	var speed := fish.velocity.length()
	if _manual_timer <= 0.0 and speed > 0.04:
		var k := 1.0 - exp(-recenter_rate * clampf(speed / fish.cruise_speed, 0.0, 1.0) * delta)
		orbit_yaw = lerp_angle(orbit_yaw, fish.yaw, k)
		orbit_pitch = lerpf(orbit_pitch, -0.25 - fish.pitch * 0.5, k)

	_pivot = _pivot.lerp(fish.global_position, 1.0 - exp(-12.0 * delta))

	var gaze_target := 1.0 if (not menu_view and Input.is_action_pressed("gaze")) else 0.0
	gaze = move_toward(gaze, gaze_target, delta / gaze_time)
	_menu = move_toward(_menu, 1.0 if menu_view else 0.0, delta / 0.6)

	var follow := _follow_transform()
	var xf := follow
	var f := FOLLOW_FOV
	if screen and gaze > 0.0:
		var gazed := _look_from(_gaze_position(), 0.85)
		xf = follow.interpolate_with(gazed[0], smoothstep(0.0, 1.0, gaze))
		f = lerpf(f, gazed[1], smoothstep(0.0, 1.0, gaze))
	if screen and _menu > 0.0:
		var menu := _look_from(_menu_position(), 0.7)
		xf = xf.interpolate_with(menu[0], smoothstep(0.0, 1.0, _menu))
		f = lerpf(f, menu[1], smoothstep(0.0, 1.0, _menu))
	global_transform = xf
	fov = f


func is_underwater() -> bool:
	return bounds.has_point(global_position)


func _follow_transform() -> Transform3D:
	var offset := Basis.from_euler(Vector3(orbit_pitch, orbit_yaw, 0.0)) * Vector3(0, 0, distance)
	var target := _pivot + Vector3(0, 0.02, 0)
	var pos := _clamp_inside(target + offset, front_leeway)
	return Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)


func _gaze_position() -> Vector3:
	var to_screen := (screen.global_position - fish.global_position).normalized()
	# Up and back far enough that the fish sits low in frame, not over the stream.
	return _clamp_inside(fish.global_position - to_screen * 0.2 + Vector3(0, 0.07, 0))


func _menu_position() -> Vector3:
	var inner := bounds.grow(-0.04)
	return Vector3(inner.end.x - 0.08, inner.get_center().y + 0.05, inner.get_center().z)


## Transform at `pos` looking at the screen, and the vertical FOV at which the
## screen fills `fill` of the view.
func _look_from(pos: Vector3, fill: float) -> Array:
	var center := screen.global_position
	var dist := pos.distance_to(center)
	var aspect := get_viewport().get_visible_rect().size.aspect() if get_viewport() else 16.0 / 9.0
	var half_h := screen_size.y * 0.5
	var half_w_as_h := screen_size.x * 0.5 / aspect
	var fit := rad_to_deg(2.0 * atan(maxf(half_h, half_w_as_h) / dist)) / fill
	return [Transform3D(Basis.looking_at(center - pos, Vector3.UP), pos), clampf(fit, 8.0, FOLLOW_FOV)]


func _clamp_inside(p: Vector3, leeway_front := 0.0) -> Vector3:
	if bounds.size == Vector3.ZERO:
		return p
	var inner := bounds.grow(-0.02)
	var clamped := p.clamp(inner.position, inner.end)
	if leeway_front > 0.0 and p.z > inner.end.z:
		clamped.z = minf(p.z, bounds.end.z + leeway_front)
	return clamped
