class_name RoomBuilder
extends RefCounted
## Builds the streamer's bedroom around the fish tank: the room model
## (art/models/room, baked lighting per mood), the tank, the monitor the fish
## watches through the tank's right glass, and the room camera on its tripod.
##
## The room is laid out in Blender (art/models/room/layout.py); layout.json
## says where things are. The room is moved so its tank spot lands on
## TANK_ORIGIN, which everything else in the game is built around.
##
##                 window
##   +------------====-------------+
##   | shelf  [  tank  ]   | desk  |
##   | bed               | [mon] |    the monitor faces -X, at the tank's
##   |           (o) camera          |    right glass
##   | door              beanbag     |
##   +-------------------------------+

const TANK_ORIGIN := Vector3(0.0, 0.8, 0.0)
## Tank interior, tank-local. Glass sits just outside it.
const TANK_INNER := AABB(Vector3(-0.6, 0.0, -0.25), Vector3(1.2, 0.6, 0.5))
const GRAVEL_TOP := 0.03
const WATER_LEVEL := 0.56
const GLASS := 0.01

## The room model's render layer: live accent lights leave it out (its light
## is baked) and light only the fish, the tank and the decor.
const ROOM_LAYER := 2
const ACCENT_MASK := 1

const LAYOUT_PATH := "res://art/room/layout.json"
const ROOM_MODEL := preload("res://art/room/room.glb")
const ROOM_SHADER := preload("res://shaders/room.gdshader")
const VIEW_SHADER := preload("res://shaders/window_view.gdshader")
const WINDOW_SHADER := preload("res://shaders/window_glass.gdshader")
const TANK_MODEL := preload("res://art/tank.glb")
const GLASS_SHADER := preload("res://shaders/tank_glass.gdshader")
const WATER_SHADER := preload("res://shaders/water_surface.gdshader")
const WATER_LOW_SHADER := preload("res://shaders/water_surface_low.gdshader")

var root: Node3D
var result := {}
var layout := {}
## Room model space to game space.
var offset := Vector3.ZERO
var moods: RoomMoods


static func build(p_root: Node3D) -> Dictionary:
	var b := RoomBuilder.new()
	b.root = p_root
	b.layout = load_layout()
	b.offset = TANK_ORIGIN - _vec(b.layout.tank_origin)
	b.moods = RoomMoods.new()
	b.moods.name = "RoomMoods"
	b._environment()
	b._room()
	b._tank()
	b._desk()
	b._accents()
	b._room_camera()
	p_root.add_child(b.moods)
	b.result.moods = b.moods
	return b.result


static func load_layout() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if data is Dictionary:
		return data
	push_error("RoomBuilder: can't read %s; build the room with art/build.sh room" % LAYOUT_PATH)
	return {}


## A layout point in game space.
func point(key: String) -> Vector3:
	return _vec(layout[key]) + offset


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.6)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.0
	env.fog_light_color = Color(0.1, 0.35, 0.38)
	env.fog_density = 0.12
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	result.environment = env
	moods.environment = env


func _room() -> void:
	var model: Node3D = ROOM_MODEL.instantiate()
	model.name = "Bedroom"
	model.position = offset
	root.add_child(model)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.layers = ROOM_LAYER
		match mi.name:
			"WindowView":
				moods.view_material = ShaderMaterial.new()
				moods.view_material.shader = VIEW_SHADER
				mi.material_override = moods.view_material
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"WindowGlass":
				moods.glass_material = ShaderMaterial.new()
				moods.glass_material.shader = WINDOW_SHADER
				var w: Array = layout.window  # centre x, sill, top, width
				moods.glass_material.set_shader_parameter("size", Vector2(w[3], w[2] - w[1]))
				mi.material_override = moods.glass_material
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_:
				for i in mi.mesh.get_surface_count():
					mi.set_surface_override_material(i, _room_material(mi.mesh.surface_get_material(i)))
	result.room_model = model


## The imported material, redone with the lightmapped room shader (one per
## Blender material, so a mood change touches each once).
func _room_material(imported: Material) -> ShaderMaterial:
	var key: String = imported.resource_name if imported else ""
	if moods.materials.has(key):
		return moods.materials[key]
	var m := ShaderMaterial.new()
	m.shader = ROOM_SHADER
	if imported is BaseMaterial3D:
		var base := imported as BaseMaterial3D
		m.set_shader_parameter("albedo", base.albedo_color)
		m.set_shader_parameter("roughness", base.roughness)
		if base.albedo_texture:
			m.set_shader_parameter("albedo_texture", base.albedo_texture)
			m.set_shader_parameter("use_texture", true)
	if key == "GlowChat":
		m.set_shader_parameter("emission_from_texture", true)
	moods.materials[key] = m
	return m


func _tank() -> void:
	var tank := Node3D.new()
	tank.name = "Tank"
	tank.position = TANK_ORIGIN
	root.add_child(tank)
	result.tank = tank
	result.tank_inner = TANK_INNER
	result.water_level = WATER_LEVEL

	# The glass, trim, hood, gravel and stand (art/models/tank.py). A few of its
	# materials get Godot's own versions by name.
	var model: Node3D = TANK_MODEL.instantiate()
	model.name = "TankModel"
	tank.add_child(model)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var imported := mi.mesh.surface_get_material(i)
			match imported.resource_name if imported else "":
				"Glass":
					var glass := ShaderMaterial.new()
					glass.shader = GLASS_SHADER
					mi.set_surface_override_material(i, glass)
				"Lamp":
					var lamp := StandardMaterial3D.new()
					lamp.albedo_color = Color(1.0, 0.97, 0.9)
					lamp.emission_enabled = true
					lamp.emission = Color(1.0, 0.96, 0.88)
					lamp.emission_energy_multiplier = 4.0
					mi.set_surface_override_material(i, lamp)
				"Gravel":
					var gravel: StandardMaterial3D = imported.duplicate()
					mi.set_surface_override_material(i, gravel)
					Quality.add_caustics(gravel)
				"Silicone":
					var silicone := StandardMaterial3D.new()
					silicone.albedo_color = Color(0.08, 0.1, 0.1, 0.75)
					silicone.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					silicone.roughness = 0.3
					mi.set_surface_override_material(i, silicone)
	var w := TANK_INNER.size.x
	var h := TANK_INNER.size.y
	var d := TANK_INNER.size.z

	# Water: a tinted volume seen from outside (back faces culled, so it vanishes
	# once the camera is inside) and a surface seen from both sides.
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.2, 0.6, 0.65, 0.14)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.1
	_box("Water", Vector3(w - 0.002, WATER_LEVEL, d - 0.002), Vector3(0, WATER_LEVEL / 2, 0), water, tank)
	var surface := MeshInstance3D.new()
	surface.name = "WaterSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, d)
	plane.subdivide_width = 60
	plane.subdivide_depth = 25
	surface.mesh = plane
	var surface_mat := ShaderMaterial.new()
	surface.material_override = surface_mat
	surface.position = Vector3(0, WATER_LEVEL, 0)
	tank.add_child(surface)
	var use_quality := func(level: int) -> void:
		surface_mat.shader = WATER_LOW_SHADER if level == 0 else WATER_SHADER
	use_quality.call(Quality.level)
	Quality.changed.connect(use_quality)
	result.water_surface = surface

	# Where the caustics shine: the water volume, in world space.
	RenderingServer.global_shader_parameter_set("tank_water_min", TANK_ORIGIN + Vector3(-w / 2, 0.0, -d / 2))
	RenderingServer.global_shader_parameter_set("tank_water_max", TANK_ORIGIN + Vector3(w / 2, WATER_LEVEL, d / 2))

	# The fish's world: gravel floor, glass walls and the water surface.
	var bounds := StaticBody3D.new()
	bounds.name = "TankBounds"
	tank.add_child(bounds)
	var t := 0.1
	_shape(bounds, Vector3(w + 2 * t, t, d + 2 * t), Vector3(0, GRAVEL_TOP - t / 2, 0))
	_shape(bounds, Vector3(w + 2 * t, t, d + 2 * t), Vector3(0, WATER_LEVEL + t / 2, 0))
	_shape(bounds, Vector3(t, h, d), Vector3(-w / 2 - t / 2, h / 2, 0))
	_shape(bounds, Vector3(t, h, d), Vector3(w / 2 + t / 2, h / 2, 0))
	_shape(bounds, Vector3(w, h, t), Vector3(0, h / 2, -d / 2 - t / 2))
	_shape(bounds, Vector3(w, h, t), Vector3(0, h / 2, d / 2 + t / 2))

	# The hood's lamp.
	var tank_light := SpotLight3D.new()
	tank_light.name = "TankLight"
	tank_light.position = Vector3(0, h + 0.004, 0.02)
	tank_light.rotation.x = -PI / 2
	tank_light.light_color = Color(0.92, 0.97, 1.0)
	tank_light.light_energy = 1.6
	tank_light.spot_range = 1.2
	tank_light.spot_angle = 72.0
	tank_light.shadow_enabled = true
	tank.add_child(tank_light)
	moods.tank_light = tank_light


## The monitor's picture (the room model has the monitor itself), its glow
## and where its speakers are.
func _desk() -> void:
	var sc := point("screen_center") + Vector3(-0.002, 0, 0)
	var size := Vector2(layout.screen_size[0], layout.screen_size[1])
	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = size
	screen.mesh = quad
	screen.position = sc
	screen.rotation.y = -PI / 2 # +Z face now points -X, at the tank
	root.add_child(screen)
	result.screen = screen
	result.screen_size = size

	# The screen's light on the desk and the fish. It's live (it lights the
	# room too), on top of the baked glow.
	var glow := OmniLight3D.new()
	glow.name = "ScreenGlow"
	glow.position = sc + Vector3(-0.3, 0, 0)
	glow.light_color = Color(0.6, 0.75, 1.0)
	glow.omni_range = 2.2
	root.add_child(glow)
	result.screen_light = glow
	moods.screen_light = glow

	var speakers: Array[Vector3] = []
	for p: Array in layout.speakers:
		speakers.append(_vec(p) + offset)
	result.speakers = speakers


## Live lights for what the bake doesn't cover: the fish, the tank and its
## decor. They leave the room's layer alone.
func _accents() -> void:
	var window_light := DirectionalLight3D.new()
	window_light.name = "WindowLight"
	window_light.light_cull_mask = ACCENT_MASK
	window_light.directional_shadow_max_distance = 8.0
	root.add_child(window_light)
	moods.window_light = window_light

	for key in ["floor_lamp", "bedside_lamp"]:
		var lamp := _accent_light("Lamp", point(key), Color(1.0, 0.72, 0.45), 5.0)
		moods.lamps.append(lamp)
	var w: Array = layout.window
	moods.fairy_light = _accent_light("FairyLights", Vector3(w[0], layout.fairy_window_y, layout.room_min[2] + 0.15) + offset,
		Color(1.0, 0.8, 0.5), 1.8)
	moods.accent_light = _accent_light("RGBAccent", point("rgb_strip") + Vector3(-0.4, -0.8, 0.0), Color.WHITE, 3.5)


func _accent_light(light_name: String, pos: Vector3, color: Color, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = pos
	light.light_color = color
	light.omni_range = reach
	light.light_cull_mask = ACCENT_MASK
	root.add_child(light)
	return light


## The camera on the tripod (the room model has the tripod): the view the
## tank cam window streams.
func _room_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "RoomCamera"
	cam.fov = 32.0
	root.add_child(cam)
	cam.look_at_from_position(point("room_camera"), TANK_ORIGIN + Vector3(0, 0.28, 0))
	result.room_camera = cam


func _box(box_name: String, size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent else root).add_child(mi)
	return mi


func _shape(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	body.add_child(shape)
