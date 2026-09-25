class_name DecorPiece
extends Node3D
## One piece of tank decor: its model, colour variant, size and rotation, its
## collision, and any bubbles, glow or water spill it has.
##
## Solid pieces are on collision layers 1 (the fish bumps into them) and 2 (the
## editor can pick them; they hide the fish from the tank cam). Soft pieces
## (plants, moss, lily pads) are only on layer 2, so the fish swims through.
##
## Collision uses convex shapes only (concave ones miss rays and ignore scale
## in Godot Physics): the model's own "-convcolonly" parts if it has them
## (the driftwood arch, the filter), otherwise one hull around the whole mesh.

const PLANT_SHADER := preload("res://shaders/plant.gdshader")
const BUBBLE_SHADER := preload("res://shaders/bubble.gdshader")
const SPILL_SHADER := preload("res://shaders/spill.gdshader")
const SIZES := ["S", "M", "L"]
const BUBBLE_SPEED := 0.14 ## m/s

var type: String
var variant := 0
var size := "M"
## Degrees about the vertical axis.
var yaw := 0.0
## No sounds (the editor's thumbnails).
var quiet := false
## Where bubbles stop rising: the water line, in this piece's parent's space.
var water_level := 0.56

## Physics for pieces the fish can push around (the moss ball), or null.
var ball: DecorBall

var _model: Node3D
var _body: StaticBody3D
var _bubbles: Array[GPUParticles3D] = []
var _glow: OmniLight3D
var _plant_materials: Array[ShaderMaterial] = []
var _selected := false


func _init(p_type: String, p_variant := 0, p_size := "M", p_yaw := 0.0) -> void:
	type = p_type
	variant = p_variant
	size = p_size
	yaw = p_yaw
	name = "Decor_" + type


func info() -> Dictionary:
	return DecorCatalog.item(type)


func is_solid() -> bool:
	return info().get("kind", "solid") == "solid"


func anchor() -> String:
	return info().get("anchor", "gravel")


func _ready() -> void:
	_build()
	Quality.changed.connect(_on_quality_changed)


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_bubbles.clear()
	_plant_materials.clear()
	_glow = null
	var ball_home: Vector3 = ball.home if ball else position
	ball = null
	rotation = Vector3(0, deg_to_rad(yaw), 0)
	scale = Vector3.ONE * DecorCatalog.size_scale(size)

	_model = DecorCatalog.scene(type).instantiate()
	add_child(_model)
	var colours := DecorCatalog.variant(type, variant)
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var imported := mi.mesh.surface_get_material(i)
			var mat_name: String = imported.resource_name if imported else ""
			mi.set_surface_override_material(i, _material_for(mat_name, colours))
	_add_body()
	var bubble_rate := 0.0
	for emitter: Dictionary in info().get("bubbles", []):
		var at: Array = emitter.at
		_add_bubbles(Vector3(at[0], at[1], at[2]), float(emitter.get("rate", 8)))
		bubble_rate += float(emitter.get("rate", 8))
	if not quiet:
		# Bubbles sound as busy as they look; the filter trickles.
		if bubble_rate > 0.0:
			Sound.loop_on(self, "bubbles", -40.0 + 10.0 * log(bubble_rate) / log(10.0), 0.8)
		if info().get("spill", false):
			Sound.loop_on(self, "trickle", -32.0, 0.8)
	if info().has("glow"):
		_glow = OmniLight3D.new()
		_glow.light_color = _colour(colours.get(info().glow, "#ff7b2b"))
		_glow.light_energy = 0.25
		_glow.omni_range = 0.12
		_glow.position = Vector3(0, 0.03, 0)
		add_child(_glow)
	if info().get("physics", "") == "ball":
		position = ball_home
		ball = DecorBall.new(self)
		add_child(ball)
	set_selected(_selected)


func model() -> Node3D:
	return _model


func _colour(hex: String) -> Color:
	return Color.html(hex)


func _material_for(mat_name: String, colours: Dictionary) -> Material:
	var tint := _colour(colours.get(mat_name, "#ffffff"))
	match mat_name:
		"Plant":
			var plant := ShaderMaterial.new()
			plant.shader = PLANT_SHADER
			plant.set_shader_parameter("tint", tint)
			plant.set_shader_parameter("caustics", 1.0 if Quality.level >= Quality.Level.MEDIUM else 0.0)
			_plant_materials.append(plant)
			return plant
		"Spill":
			var spill := ShaderMaterial.new()
			spill.shader = SPILL_SHADER
			return spill
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.roughness = {"Accent": 0.35, "Secondary": 0.5}.get(mat_name, 0.8)
	if mat_name == "Secondary" and type == "bonfire":
		m.metallic = 0.8
		m.roughness = 0.3
	if mat_name == info().get("glow", ""):
		m.emission_enabled = true
		m.emission = tint
		m.emission_energy_multiplier = 1.2
	Quality.add_caustics(m)
	return m


func _add_body() -> void:
	var layer := (1 | 2) if is_solid() else 2
	var imported := _model.find_children("*", "StaticBody3D", true, false)
	for body: StaticBody3D in imported:
		body.collision_layer = layer
		body.collision_mask = 0
	if not imported.is_empty():
		_body = imported[0]
		return
	_body = StaticBody3D.new()
	_body.collision_layer = layer
	_body.collision_mask = 0
	add_child(_body)
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var shape := CollisionShape3D.new()
		shape.shape = mi.mesh.create_convex_shape()
		shape.transform = _model.transform * mi.transform
		_body.add_child(shape)


func _add_bubbles(at: Vector3, rate: float) -> void:
	var p := GPUParticles3D.new()
	p.name = "Bubbles"
	p.position = at
	# Rise to the surface: lifetime from how far below it the emitter is.
	var height := maxf(water_level - (position.y + at.y * scale.y), 0.05)
	p.lifetime = height / BUBBLE_SPEED
	p.amount = maxi(1, int(rate * p.lifetime * Quality.particle_scale()))
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-0.1, -0.05, -0.1), Vector3(0.2, height + 0.1, 0.2))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 6.0
	process.initial_velocity_min = BUBBLE_SPEED * 0.85
	process.initial_velocity_max = BUBBLE_SPEED * 1.15
	process.gravity = Vector3.ZERO
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.006
	process.scale_min = 0.6
	process.scale_max = 1.5
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.4
	process.turbulence_noise_scale = 3.0
	process.turbulence_influence_min = 0.02
	process.turbulence_influence_max = 0.06
	p.process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.0022
	mesh.height = 0.0044
	mesh.radial_segments = 10
	mesh.rings = 6
	var mat := ShaderMaterial.new()
	mat.shader = BUBBLE_SHADER
	mesh.material = mat
	p.draw_pass_1 = mesh
	add_child(p)
	_bubbles.append(p)


func _on_quality_changed(_level: int) -> void:
	for p in _bubbles:
		var rate := p.amount / maxf(p.lifetime, 0.01) / maxf(Quality.particle_scale(), 0.01)
		p.amount = maxi(1, int(rate * p.lifetime * Quality.particle_scale()))
	for m in _plant_materials:
		m.set_shader_parameter("caustics", 1.0 if Quality.level >= Quality.Level.MEDIUM else 0.0)


## Rebuilds after a change of type-independent settings.
func set_look(p_variant: int, p_size: String, p_yaw: float) -> void:
	variant = p_variant
	size = p_size
	yaw = p_yaw
	if is_inside_tree():
		_build()


func set_yaw(p_yaw: float) -> void:
	yaw = wrapf(p_yaw, 0.0, 360.0)
	rotation = Vector3(0, deg_to_rad(yaw), 0)


## Bounds in the parent's space (for placement checks).
func bounds() -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = transform * (_model.transform * mi.transform) * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## Whether any of the piece's triangles reach into `box` (parent's space).
## Finer than its bounds: a filter's tall intake and wide body only overlap
## where they really are.
func intersects(box: AABB) -> bool:
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var xf := transform * _model.transform * mi.transform
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var tri := AABB(xf * faces[i], Vector3.ZERO).expand(xf * faces[i + 1]).expand(xf * faces[i + 2])
			if tri.intersects(box):
				return true
	return false


## Editor highlight: a faint outline box.
func set_selected(value: bool) -> void:
	_selected = value
	var old := get_node_or_null("Selection")
	if old:
		old.queue_free()
	if not value or _model == null:
		return
	var box := MeshInstance3D.new()
	box.name = "Selection"
	var mesh := BoxMesh.new()
	var local := AABB()
	var first := true
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (_model.transform * mi.transform) * mi.get_aabb()
		local = b if first else local.merge(b)
		first = false
	mesh.size = local.size + Vector3.ONE * 0.006
	box.mesh = mesh
	box.position = local.get_center()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2, 0.18)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material_override = mat
	add_child(box)


func to_dict() -> Dictionary:
	# A ball saves where it was put, not where the fish pushed it.
	var p: Vector3 = ball.home if ball else position
	return {
		"type": type,
		"position": [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)],
		"yaw": snappedf(yaw, 0.5),
		"size": size,
		"variant": variant,
	}
