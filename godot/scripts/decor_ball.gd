class_name DecorBall
extends Node
## Makes a round decor piece (the moss ball) something the fish can push
## around, like a beach ball in water: no gravity, light and bouncy. The fish
## knocks it along the contact normal (harder the faster it's going) without
## being slowed itself; the ball drifts on, slows in the water, rolls as it
## goes, and bounces off the glass, the gravel, the surface and solid decor.
##
## It moves its DecorPiece (the parent) directly. `home` is where the tank
## editor put it, which is what gets saved; pushing it around doesn't change
## the layout.

const FISH_RADIUS := 0.018       ## the fish's collision capsule (main.gd)
const FISH_HALF_LENGTH := 0.022  ## half the capsule's straight part, along Z
const PUSH := 1.4                ## how much of the fish's closing speed the ball takes (light ball)
const BOUNCE := 0.55             ## restitution off walls and decor
const DRAG := 0.9                ## 1/s: water slows it
const ROLL_DRAG := 1.4           ## 1/s: and its spin
const MAX_SPEED := 0.6           ## m/s
const SOLID_MASK := 1            ## tank bounds and solid decor

var piece: DecorPiece
var velocity := Vector3.ZERO     ## parent space (the tank), m/s
var spin := Vector3.ZERO         ## rad/s, parent space
var home := Vector3.ZERO
## Seconds since the last knock worth a sound.
var _since_bump := 1.0
var _radius := 0.0
var _shape := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


func _init(p_piece: DecorPiece) -> void:
	piece = p_piece
	name = "Ball"


func _ready() -> void:
	home = piece.position
	_radius = piece.bounds().size.x * 0.5  # before it has rolled (a turned box's bounds grow)
	_query.shape = _shape
	_query.collision_mask = SOLID_MASK


## The ball's radius in the tank's space.
func radius() -> float:
	return _radius


## Put back at `pos` and stilled (the editor moved it, or a layout loaded).
func place(pos: Vector3) -> void:
	home = pos
	piece.position = pos
	velocity = Vector3.ZERO
	spin = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not piece.is_inside_tree() or delta <= 0.0:
		return
	_since_bump += delta
	var r := radius()
	_fish_contact(r)
	if velocity.length_squared() < 1e-10 and spin.length_squared() < 1e-8:
		return
	velocity = velocity.limit_length(MAX_SPEED)
	piece.position += velocity * delta
	_bounce(r)
	# Water drag.
	velocity *= exp(-DRAG * delta)
	# Roll: spin follows the motion (as if rolling on the water it pushes
	# aside), and fades.
	var roll := Vector3.UP.cross(velocity) / maxf(r, 0.005)
	spin = spin.lerp(roll, 1.0 - exp(-3.0 * delta)) * exp(-ROLL_DRAG * delta)
	var model := piece.model()
	if model and spin.length() > 1e-4:
		# Spin is in tank space; turn it into the piece's own (yawed) space.
		var axis := (piece.basis.orthonormalized().inverse() * spin).normalized()
		model.basis = Basis(axis, spin.length() * delta) * model.basis
		model.basis = model.basis.orthonormalized()
	if velocity.length() < 0.002 and spin.length() < 0.05:
		velocity = Vector3.ZERO
		spin = Vector3.ZERO


## The fish nosing or bumping into the ball.
func _fish_contact(r: float) -> void:
	var fish := _fish()
	if fish == null:
		return
	_query.exclude = [fish.get_rid()]
	var parent := piece.get_parent() as Node3D
	var to_local := parent.global_transform.affine_inverse()
	# The fish's capsule as a segment, in the tank's space.
	var fx := to_local * fish.global_transform
	var a := fx * Vector3(0, 0, -FISH_HALF_LENGTH)
	var b := fx * Vector3(0, 0, FISH_HALF_LENGTH)
	var c := piece.position
	var closest := Geometry3D.get_closest_point_to_segment(c, a, b)
	var d := c - closest
	var dist := d.length()
	var reach := r + FISH_RADIUS
	if dist >= reach:
		return
	var n := d / dist if dist > 1e-5 else (to_local.basis * -fish.global_basis.z).normalized()
	# Out of the fish, then knocked away by how fast the fish closes on it.
	piece.position += n * (reach - dist)
	var fish_v := to_local.basis * fish.velocity
	var closing := (fish_v - velocity).dot(n)
	if closing > 0.0:
		velocity += n * closing * PUSH
		# A glancing knock sets it spinning.
		var tangential := (fish_v - velocity) - n * (fish_v - velocity).dot(n)
		spin += n.cross(tangential) / maxf(r, 0.005) * -0.5
		if closing > 0.05 and _since_bump > 0.25:
			_since_bump = 0.0
			Sound.play_at("bump", piece.global_position, lerpf(-30.0, -19.0, clampf(closing / 0.5, 0.0, 1.0)), 0.15, 0.5)
	elif velocity.dot(n) < 0.0:
		velocity -= n * velocity.dot(n)


## Off the glass, gravel, surface and solid decor.
func _bounce(r: float) -> void:
	var decor := piece.get_parent() as TankDecor
	if decor:
		var w := decor.water
		for axis in 3:
			var lo := w.position[axis] + r
			var hi := w.end[axis] - r
			if piece.position[axis] < lo:
				piece.position[axis] = lo
				velocity[axis] = absf(velocity[axis]) * BOUNCE
			elif piece.position[axis] > hi:
				piece.position[axis] = hi
				velocity[axis] = -absf(velocity[axis]) * BOUNCE
	var space := piece.get_world_3d().direct_space_state if piece.is_inside_tree() else null
	if space == null:
		return
	var scale := (piece.get_parent() as Node3D).global_basis.get_scale().x if piece.get_parent() is Node3D else 1.0
	_shape.radius = r * scale
	for i in 3:
		_query.transform = Transform3D(Basis(), piece.global_position)
		var hit := space.get_rest_info(_query)
		if hit.is_empty():
			return
		var parent_inv := (piece.get_parent() as Node3D).global_transform.affine_inverse()
		var n: Vector3 = (parent_inv.basis * (hit.normal as Vector3)).normalized()
		var p: Vector3 = parent_inv * (hit.point as Vector3)
		# Out of the obstacle along its normal, and bounce.
		var depth := r - (piece.position - p).dot(n)
		if depth <= 0.0:
			return
		piece.position += n * (depth + 0.0005)
		var into := velocity.dot(n)
		if into < 0.0:
			velocity -= n * into * (1.0 + BOUNCE)


func _fish() -> Fish:
	var fishes := piece.get_tree().get_nodes_in_group("fish")
	return fishes[0] as Fish if not fishes.is_empty() else null
