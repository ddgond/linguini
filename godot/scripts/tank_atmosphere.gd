class_name TankAtmosphere
extends Node3D
## What makes the water feel like water: faint motes drifting in it, and soft
## shafts of light falling from the lamp. Motes scale with the quality preset;
## the shafts are off on Low. Add as a child of the tank.

const MOTES := [70, 160, 320] ## by Quality level
const SHAFTS := 5
const MOTE_SHADER := preload("res://shaders/mote.gdshader")
const SHAFT_SHADER := preload("res://shaders/light_shaft.gdshader")

## The water, in the tank's space.
var water := AABB()

var motes: GPUParticles3D
var shafts: Array[MeshInstance3D] = []


func _ready() -> void:
	motes = GPUParticles3D.new()
	motes.name = "Motes"
	motes.lifetime = 14.0
	motes.preprocess = 14.0
	motes.local_coords = true
	motes.visibility_aabb = AABB(water.position - Vector3.ONE * 0.05, water.size + Vector3.ONE * 0.1)
	motes.position = Vector3.ZERO
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = water.size / 2.0 * Vector3(0.96, 0.9, 0.92)
	process.gravity = Vector3(0, -0.0015, 0)
	process.direction = Vector3(0, 1, 0)
	process.spread = 180.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.006
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	process.turbulence_noise_scale = 3.0
	process.turbulence_influence_min = 0.01
	process.turbulence_influence_max = 0.03
	process.scale_min = 0.5
	process.scale_max = 1.4
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.15, 1.0))
	fade.add_point(Vector2(0.85, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	var fade_tex := CurveTexture.new()
	fade_tex.curve = fade
	process.alpha_curve = fade_tex
	motes.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.0022, 0.0022)
	var mat := ShaderMaterial.new()
	mat.shader = MOTE_SHADER
	quad.material = mat
	motes.draw_pass_1 = quad
	motes.position = water.get_center()
	add_child(motes)

	# Shafts: tall soft planes under the lamp, leaning a little, facing the room.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in SHAFTS:
		var shaft := MeshInstance3D.new()
		shaft.name = "Shaft%d" % i
		var plane := QuadMesh.new()
		# Short of the gravel, so the shaft never cuts into it.
		var height := water.size.y * 0.8
		plane.size = Vector2(rng.randf_range(0.08, 0.16), height)
		shaft.mesh = plane
		var sm := ShaderMaterial.new()
		sm.shader = SHAFT_SHADER
		sm.set_shader_parameter("half_height", height / 2.0)
		sm.set_shader_parameter("seed", rng.randf() * 10.0)
		sm.set_shader_parameter("strength", rng.randf_range(0.05, 0.09))
		shaft.material_override = sm
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var x := lerpf(water.position.x + 0.15, water.end.x - 0.15, (i + 0.5) / SHAFTS) + rng.randf_range(-0.05, 0.05)
		shaft.position = Vector3(x, water.end.y - height / 2.0, rng.randf_range(-0.12, 0.12))
		shaft.rotation = Vector3(0, rng.randf_range(-0.4, 0.4), rng.randf_range(-0.12, 0.12))
		add_child(shaft)
		shafts.append(shaft)

	_apply(Quality.level)
	Quality.changed.connect(_apply)


func _apply(level: int) -> void:
	motes.amount = MOTES[level]
	for shaft in shafts:
		shaft.visible = level >= Quality.Level.MEDIUM
