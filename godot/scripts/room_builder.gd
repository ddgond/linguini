class_name RoomBuilder
extends RefCounted
## Builds the greybox streamer bedroom: the fish tank, the desk and monitor to
## its right, and the room camera pointed at the tank's front glass.
##
## Layout (metres, +Y up, the room camera looks down -Z at the tank):
##
##          back wall
##   +------------------------------+
##   |      [ tank ]    | desk |    |
##   |     (glass +Z)   | [mon]|    |    the monitor faces -X, so the fish
##   |                  |______|    |    sees it through the tank's right glass
##   |       (o) room camera        |
##   +------------------------------+

const TANK_ORIGIN := Vector3(0.0, 0.8, 0.0)
## Tank interior, tank-local. Glass sits just outside it.
const TANK_INNER := AABB(Vector3(-0.6, 0.0, -0.25), Vector3(1.2, 0.6, 0.5))
const GRAVEL_TOP := 0.03
const WATER_LEVEL := 0.56
const GLASS := 0.01

const SCREEN_CENTER := Vector3(1.62, 1.12, 0.0)
const SCREEN_SIZE := Vector2(0.8, 0.45)
const ROOM_CAMERA_POS := Vector3(0.0, 1.08, 1.6)

const TANK_MODEL := preload("res://art/tank.glb")
const GLASS_SHADER := preload("res://shaders/tank_glass.gdshader")
const WATER_SHADER := preload("res://shaders/water_surface.gdshader")
const WATER_LOW_SHADER := preload("res://shaders/water_surface_low.gdshader")

var root: Node3D
var result := {}


static func build(p_root: Node3D) -> Dictionary:
	var b := RoomBuilder.new()
	b.root = p_root
	b._environment()
	b._room()
	b._tank()
	b._desk()
	b._room_camera()
	return b.result


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.6)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.2
	env.fog_light_color = Color(0.1, 0.35, 0.38)
	env.fog_density = 0.12
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	result.environment = env

	var ceiling := OmniLight3D.new()
	ceiling.position = Vector3(0.4, 2.35, 0.9)
	ceiling.light_color = Color(1.0, 0.86, 0.7)
	ceiling.light_energy = 1.4
	ceiling.omni_range = 5.0
	ceiling.shadow_enabled = true
	root.add_child(ceiling)


func _room() -> void:
	var floor_mat := _mat(Color(0.42, 0.3, 0.2), 0.7)
	var wall_mat := _mat(Color(0.3, 0.32, 0.42), 0.9)
	_box("Floor", Vector3(5.0, 0.02, 4.0), Vector3(0.3, -0.01, 0.8), floor_mat)
	_box("Ceiling", Vector3(5.0, 0.02, 4.0), Vector3(0.3, 2.61, 0.8), _mat(Color(0.8, 0.8, 0.8), 1.0))
	_box("BackWall", Vector3(5.0, 2.6, 0.02), Vector3(0.3, 1.3, -1.2), wall_mat)
	_box("FrontWall", Vector3(5.0, 2.6, 0.02), Vector3(0.3, 1.3, 2.8), wall_mat)
	_box("LeftWall", Vector3(0.02, 2.6, 4.0), Vector3(-2.2, 1.3, 0.8), wall_mat)
	_box("RightWall", Vector3(0.02, 2.6, 4.0), Vector3(2.8, 1.3, 0.8), wall_mat)

	# Streamer-bedroom dressing.
	_box("Rug", Vector3(1.8, 0.01, 1.2), Vector3(0.2, 0.005, 1.2), _mat(Color(0.5, 0.15, 0.2), 1.0))
	_box("Bed", Vector3(1.0, 0.45, 2.0), Vector3(-1.65, 0.225, 1.6), _mat(Color(0.25, 0.3, 0.55), 0.9))
	_box("Pillow", Vector3(0.7, 0.12, 0.35), Vector3(-1.65, 0.5, 0.8), _mat(Color(0.9, 0.9, 0.85), 1.0))
	var led := _mat(Color(0.6, 0.1, 0.9), 0.5)
	led.emission_enabled = true
	led.emission = Color(0.6, 0.15, 1.0)
	led.emission_energy_multiplier = 4.0
	_box("LedStrip", Vector3(4.0, 0.02, 0.02), Vector3(0.3, 2.2, -1.18), led)
	_poster(Vector3(-1.0, 1.5, -1.185), "GIT GUD", Color(0.9, 0.55, 0.1))
	_poster(Vector3(2.785, 1.5, 1.3), "FISH CAN\nDO ANYTHING", Color(0.15, 0.6, 0.7), -PI / 2)


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


func _desk() -> void:
	var wood := _mat(Color(0.55, 0.4, 0.28), 0.6)
	var black := _mat(Color(0.04, 0.04, 0.05), 0.35)
	_box("DeskTop", Vector3(0.7, 0.04, 1.8), Vector3(1.6, 0.73, 0.0), wood)
	for x in [1.3, 1.9]:
		for z in [-0.85, 0.85]:
			_box("DeskLeg", Vector3(0.04, 0.71, 0.04), Vector3(x, 0.355, z), wood)

	var sc := SCREEN_CENTER
	_box("MonitorBezel", Vector3(0.03, SCREEN_SIZE.y + 0.03, SCREEN_SIZE.x + 0.03), sc + Vector3(0.017, 0, 0), black)
	_box("MonitorNeck", Vector3(0.04, 0.3, 0.06), Vector3(sc.x + 0.05, 0.9, sc.z), black)
	_box("MonitorFoot", Vector3(0.2, 0.015, 0.3), Vector3(sc.x + 0.03, 0.757, sc.z), black)

	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = SCREEN_SIZE
	screen.mesh = quad
	screen.position = sc
	screen.rotation.y = -PI / 2 # +Z face now points -X, at the tank
	root.add_child(screen)
	result.screen = screen
	result.screen_size = SCREEN_SIZE

	var glow := OmniLight3D.new()
	glow.position = sc + Vector3(-0.25, 0, 0)
	glow.light_color = Color(0.6, 0.75, 1.0)
	glow.light_energy = 0.5
	glow.omni_range = 1.6
	root.add_child(glow)
	result.screen_light = glow

	var speaker_mat := _mat(Color(0.1, 0.1, 0.11), 0.5)
	var speakers: Array[Vector3] = []
	for z in [-0.6, 0.6]:
		var pos := Vector3(1.66, 0.87, z)
		_box("Speaker", Vector3(0.14, 0.24, 0.13), pos, speaker_mat)
		var cone := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.04
		cyl.height = 0.005
		cone.mesh = cyl
		cone.material_override = _mat(Color(0.2, 0.2, 0.22), 0.8)
		cone.rotation.z = PI / 2
		cone.position = pos + Vector3(-0.071, -0.03, 0)
		root.add_child(cone)
		speakers.append(pos)
	result.speakers = speakers

	_box("Keyboard", Vector3(0.16, 0.02, 0.45), Vector3(1.4, 0.76, 0.0), black)
	_box("PC", Vector3(0.45, 0.45, 0.2), Vector3(1.65, 0.23, -0.7), black)
	var rgb := _mat(Color(0.1, 0.9, 0.6), 0.3)
	rgb.emission_enabled = true
	rgb.emission = Color(0.1, 1.0, 0.7)
	rgb.emission_energy_multiplier = 3.0
	_box("PCGlow", Vector3(0.4, 0.01, 0.005), Vector3(1.65, 0.4, -0.598), rgb)
	_box("ChairSeat", Vector3(0.5, 0.08, 0.5), Vector3(1.05, 0.48, 0.85), _mat(Color(0.7, 0.1, 0.12), 0.6))
	_box("ChairBack", Vector3(0.08, 0.7, 0.5), Vector3(1.3, 0.85, 0.85), _mat(Color(0.7, 0.1, 0.12), 0.6))


func _room_camera() -> void:
	var metal := _mat(Color(0.15, 0.15, 0.16), 0.4, 0.6)
	var base := ROOM_CAMERA_POS
	for i in 3:
		var angle := TAU * i / 3.0
		var leg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.008
		cyl.bottom_radius = 0.008
		cyl.height = 1.08
		leg.mesh = cyl
		leg.material_override = metal
		var foot := base + Vector3(cos(angle), 0, sin(angle)) * 0.3
		foot.y = 0.0
		var top := base - Vector3(0, 0.06, 0)
		cyl.height = foot.distance_to(top)
		leg.position = (foot + top) / 2.0
		leg.basis = Basis(Quaternion(Vector3.UP, (top - foot).normalized()))
		root.add_child(leg)
	_box("CameraBody", Vector3(0.12, 0.09, 0.16), base, _mat(Color(0.08, 0.08, 0.09), 0.5))
	var lens := MeshInstance3D.new()
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = 0.035
	lens_mesh.bottom_radius = 0.04
	lens_mesh.height = 0.08
	lens.mesh = lens_mesh
	lens.material_override = metal
	lens.rotation.x = PI / 2
	lens.position = base + Vector3(0, 0, -0.12)
	root.add_child(lens)
	var tally := _mat(Color(1, 0, 0), 0.3)
	tally.emission_enabled = true
	tally.emission = Color(1, 0.05, 0.05)
	tally.emission_energy_multiplier = 6.0
	_box("TallyLight", Vector3(0.015, 0.015, 0.01), base + Vector3(0.04, 0.035, -0.081), tally)

	# The view the tracking stream will broadcast (milestone 2).
	var cam := Camera3D.new()
	cam.name = "RoomCamera"
	cam.fov = 32.0
	root.add_child(cam)
	cam.look_at_from_position(base + Vector3(0, 0, -0.17), TANK_ORIGIN + Vector3(0, 0.28, 0))
	result.room_camera = cam


func _poster(pos: Vector3, text: String, color: Color, yaw := 0.0) -> void:
	var poster := Node3D.new()
	poster.position = pos
	poster.rotation.y = yaw
	root.add_child(poster)
	_box("Poster", Vector3(0.6, 0.8, 0.005), Vector3.ZERO, _mat(color, 0.9), poster)
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.0012
	label.outline_size = 12
	label.position = Vector3(0, 0, 0.004)
	poster.add_child(label)


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


static func _mat(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m
