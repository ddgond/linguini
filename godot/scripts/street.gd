class_name Street
extends Node3D
## The neighbourhood outside the bedroom window (res://art/street/street.glb,
## made by art/models/street): rowhouses and shops across the road, a cross
## street, taller blocks behind and downtown in the distance, under a sky dome.
##
## It sits on its own render layer, lit by its own sun (or moon), street lamps
## and shop lights, so the room's baked light and live accents stay apart.
## Ambient light, sky reflections and haze come from global shader uniforms
## (street.gdshaderinc) that apply_mood() sets. The traffic signals cycle and
## cars drive past, stopping at red.
##
## Placed with the room model's offset: layout.json is in the room model's
## coordinates, like the room's own layout.

const MODEL := preload("res://art/street/street.glb")
const LAYOUT_PATH := "res://art/street/layout.json"
const SURFACE := preload("res://shaders/street_surface.gdshader")
const WINDOW := preload("res://shaders/street_window.gdshader")
const GLOW := preload("res://shaders/street_glow.gdshader")
const LEAVES := preload("res://shaders/street_leaves.gdshader")
const SKYLINE := preload("res://shaders/street_skyline.gdshader")
const SKY := preload("res://shaders/street_sky.gdshader")
const RAILING := preload("res://shaders/street_railing.gdshader")
const WALKER := preload("res://shaders/street_walker.gdshader")
const BIRD := preload("res://shaders/street_bird.gdshader")
const RAIN := preload("res://shaders/street_rain.gdshader")

## The street's render layer (layer 3). Its lights light only this layer.
const LAYER := 4

## Surface materials: shader kind (street_surface.gdshader), roughness, metallic, gloss.
const SURFACES := {
	"Brick": [1, 0.9, 0.0, 0.0], "Stucco": [10, 0.85, 0.0, 0.0], "Stone": [11, 0.8, 0.0, 0.0],
	"Siding": [13, 0.8, 0.0, 0.0], "GhostPaint": [14, 0.9, 0.0, 0.0],
	"Trim": [0, 0.55, 0.0, 0.05], "Wood": [12, 0.6, 0.0, 0.03], "Roof": [4, 0.95, 0.0, 0.0],
	"Asphalt": [2, 0.9, 0.0, 0.0], "Concrete": [3, 0.9, 0.0, 0.0], "Curb": [11, 0.85, 0.0, 0.0],
	"RoadPaint": [0, 0.7, 0.0, 0.0], "Soil": [0, 1.0, 0.0, 0.0], "Metal": [5, 0.45, 0.6, 0.1],
	"MetalPaint": [0, 0.4, 0.0, 0.1], "Iron": [0, 0.55, 0.3, 0.0], "Brass": [0, 0.3, 1.0, 0.1],
	"Grate": [0, 0.75, 0.0, 0.0],
	"Wire": [0, 0.6, 0.0, 0.0], "Bark": [6, 0.95, 0.0, 0.0], "Foliage": [0, 0.8, 0.0, 0.0],
	"Awning": [7, 0.9, 0.0, 0.0], "SignPaint": [0, 0.5, 0.0, 0.0], "SignalHousing": [0, 0.6, 0.0, 0.0],
	"CarPaint": [8, 0.3, 0.3, 0.6], "CarGlass": [9, 0.05, 0.0, 1.0], "Rubber": [0, 0.9, 0.0, 0.0],
	"Chrome": [5, 0.2, 1.0, 0.3], "Plate": [0, 0.5, 0.0, 0.0],
}
## Glowing materials, by mood-set group.
const GLOWS := ["Lamp", "Neon", "Headlight", "Taillight", "Signal"]
## Materials with shaders of their own.
const SPECIAL := ["Window", "Skyline", "LeafCards", "Railing", "Walker", "Umbrella", "Bird"]

## Each mood's sky, light and life. Colours are linear-ish; energies are Godot's.
const MOODS := {
	"night": {
		"zenith": Color(0.012, 0.018, 0.045), "horizon": Color(0.07, 0.065, 0.1), "haze": Color(0.075, 0.068, 0.095),
		"haze_density": 0.0016, "amb_sky": Color(0.03, 0.04, 0.075), "amb_ground": Color(0.035, 0.028, 0.022),
		"sun_dir": Vector3(-0.35, 0.3, -1.0), "sun_color": Color(0.55, 0.65, 0.95), "sun_energy": 0.15, "sun_shadow": false,
		"clouds": 0.3, "cloud_color": Color(0.05, 0.05, 0.075), "stars": 1.0, "moon": 1.0,
		"wet": 0.0, "night": 1.0, "windows_lit": 0.45, "interior": 1.0,
		"lamp": 7.0, "lamp_glow": 6.0, "neon": 4.0, "shop": 1.6, "head": 6.0, "wind": 0.6, "people": 7, "birds": false,
	},
	"rainy": {
		"zenith": Color(0.12, 0.14, 0.18), "horizon": Color(0.22, 0.23, 0.27), "haze": Color(0.19, 0.2, 0.24),
		"haze_density": 0.012, "amb_sky": Color(0.14, 0.155, 0.19), "amb_ground": Color(0.05, 0.05, 0.055),
		"sun_dir": Vector3(0.1, 0.6, -1.0), "sun_color": Color(0.7, 0.75, 0.85), "sun_energy": 0.0, "sun_shadow": false,
		"clouds": 1.0, "cloud_color": Color(0.2, 0.21, 0.25), "stars": 0.0, "moon": 0.0,
		"wet": 1.0, "night": 0.65, "windows_lit": 0.62, "interior": 0.9,
		"lamp": 5.0, "lamp_glow": 5.0, "neon": 3.5, "shop": 1.3, "head": 5.0, "wind": 1.0, "people": 6, "birds": false,
	},
	"golden": {
		"zenith": Color(0.17, 0.3, 0.6), "horizon": Color(0.82, 0.45, 0.2), "haze": Color(0.7, 0.44, 0.27),
		"haze_density": 0.0035, "amb_sky": Color(0.36, 0.33, 0.4), "amb_ground": Color(0.3, 0.18, 0.1),
		"sun_dir": Vector3(0.3, 0.75, -1.0), "sun_color": Color(1.0, 0.62, 0.32), "sun_energy": 3.2, "sun_shadow": true,
		"clouds": 0.45, "cloud_color": Color(0.95, 0.58, 0.4), "stars": 0.0, "moon": 0.0,
		"wet": 0.0, "night": 0.0, "windows_lit": 0.07, "interior": 0.6,
		"lamp": 0.0, "lamp_glow": 0.0, "neon": 1.2, "shop": 0.3, "head": 0.0, "wind": 0.8, "people": 14, "birds": true,
	},
}

## Signal timing (seconds): main street green, amber, all red, cross street
## green, amber, all red.
const CYCLE := [22.0, 3.5, 1.5, 14.0, 3.5, 1.5]

var layout := {}
var mood := ""
## The street_* shader globals as last set (the renderer can't be asked).
var globals := {}
var sun: DirectionalLight3D
var _surfaces := {}
var _glows := {}
var _moving_glows := {}
var _leaves: ShaderMaterial
var _lamps: Array[OmniLight3D] = []
var _shop_lights: Array[OmniLight3D] = []
var _neon_lights: Array[OmniLight3D] = []
var _templates: Array[MeshInstance3D] = []
var _rain_sheets: Array[MeshInstance3D] = []
var _cars: Array[Dictionary] = []
var _walker_templates: Array[MeshInstance3D] = []
var _umbrella: MeshInstance3D
var _walkers: Array[Dictionary] = []
var _bird: MeshInstance3D
var _flock: Node3D
var _flock_t := 0.0
var _next_flock := 2.0
var _next_car := [2.0, 5.0]
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	_model()
	_sky()
	_rain()
	_lights()
	Quality.changed.connect(_apply_quality)
	_apply_quality(Quality.level)


func _model() -> void:
	var model: Node3D = MODEL.instantiate()
	model.name = "Model"
	add_child(model)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.layers = LAYER
		var moving := mi.name.begins_with("CarTemplate_")
		for i in mi.mesh.get_surface_count():
			var imported := mi.mesh.surface_get_material(i)
			var mat_name: String = imported.resource_name if imported else ""
			mi.set_surface_override_material(i, _material(mat_name, imported, moving))
		if moving:
			mi.visible = false
			_templates.append(mi)
		elif mi.name.begins_with("Walker_"):
			mi.visible = false
			_walker_templates.append(mi)
		elif mi.name == "Umbrella":
			mi.visible = false
			_umbrella = mi
		elif mi.name == "Bird":
			mi.visible = false
			_bird = mi
		# The leaf cards are thin: no shadows from their back faces' angle games.
		if mi.name == "Skyline" or mi.name == "Ground":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _material(mat_name: String, imported: Material, moving: bool) -> Material:
	var cache: Dictionary = _moving_glows if moving and mat_name in GLOWS else _surfaces
	if cache.has(mat_name):
		return cache[mat_name]
	var m := ShaderMaterial.new()
	if SURFACES.has(mat_name):
		var s: Array = SURFACES[mat_name]
		m.shader = SURFACE
		m.set_shader_parameter("kind", s[0])
		m.set_shader_parameter("roughness", s[1])
		m.set_shader_parameter("metallic", s[2])
		m.set_shader_parameter("gloss", s[3])
		m.set_shader_parameter("two_sided", mat_name in ["Awning", "Wire", "SignPaint"])
	elif mat_name == "Window":
		m.shader = WINDOW
	elif mat_name == "Skyline":
		m.shader = SKYLINE
	elif mat_name == "Railing":
		m.shader = RAILING
	elif mat_name == "Walker":
		m.shader = WALKER
	elif mat_name == "Bird":
		m.shader = BIRD
	elif mat_name == "Umbrella":
		m.shader = SURFACE
		m.set_shader_parameter("kind", 8)
		m.set_shader_parameter("roughness", 0.3)
		m.set_shader_parameter("gloss", 0.5)
		m.set_shader_parameter("two_sided", true)
	elif mat_name == "LeafCards":
		m.shader = LEAVES
		if imported is BaseMaterial3D:
			m.set_shader_parameter("atlas", (imported as BaseMaterial3D).albedo_texture)
		_leaves = m
	elif mat_name in GLOWS:
		m.shader = GLOW
		m.set_shader_parameter("signal", mat_name == "Signal")
		m.set_shader_parameter("flicker", 0.6 if mat_name == "Neon" else 0.0)
		if not moving:
			_glows[mat_name] = m
	else:
		m.shader = SURFACE
		push_warning("Street: no material for %s" % mat_name)
	cache[mat_name] = m
	return m


## A dome for the sky, far out, on the street's layer.
func _sky() -> void:
	var dome := MeshInstance3D.new()
	dome.name = "Sky"
	var sphere := SphereMesh.new()
	sphere.radius = 2400.0
	sphere.height = 4800.0
	sphere.radial_segments = 48
	sphere.rings = 24
	dome.mesh = sphere
	var m := ShaderMaterial.new()
	m.shader = SKY
	dome.material_override = m
	dome.layers = LAYER
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.custom_aabb = AABB(Vector3(-1, -1, -1) * 3000.0, Vector3.ONE * 6000.0)
	add_child(dome)


## Sheets of falling rain between the window and the far side of the street,
## at several depths, near ones coarser and closer together.
func _rain() -> void:
	var road: float = layout.road_y
	for spec: Array in [[-2.8, 1.6, 0.35, 0.5], [-5.0, 2.2, 0.4, 0.4], [-8.0, 3.0, 0.5, 0.35], [-12.0, 4.0, 0.55, 0.3],
			[-17.0, 5.0, 0.6, 0.25]]:
		var sheet := MeshInstance3D.new()
		sheet.name = "Rain"
		var quad := QuadMesh.new()
		quad.size = Vector2(70.0, 22.0)
		sheet.mesh = quad
		sheet.position = Vector3(0.0, road + 11.0, spec[0])
		var m := ShaderMaterial.new()
		m.shader = RAIN
		m.set_shader_parameter("size", quad.size)
		m.set_shader_parameter("density", spec[1])
		m.set_shader_parameter("streak", spec[2])
		m.set_shader_parameter("strength", spec[3])
		sheet.material_override = m
		sheet.layers = LAYER
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sheet.visible = false
		add_child(sheet)
		_rain_sheets.append(sheet)


func _lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "StreetSun"
	sun.light_cull_mask = LAYER
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.5
	add_child(sun)
	for p: Array in layout.lamps:
		var lamp := _light(Vector3(p[0], p[1], p[2]), Color(1.0, 0.76, 0.48), 18.0)
		lamp.omni_attenuation = 1.3
		_lamps.append(lamp)
	for p: Array in layout.shops:
		_shop_lights.append(_light(Vector3(p[0], p[1], p[2]), Color(1.0, 0.85, 0.65), 6.0))
	for n: Dictionary in layout.neon:
		var p: Array = n.pos
		var c: Array = n.color
		_neon_lights.append(_light(Vector3(p[0], p[1], p[2]), Color(c[0], c[1], c[2]), 4.5))


func _light(pos: Vector3, color: Color, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.omni_range = reach
	light.light_cull_mask = LAYER
	light.light_specular = 0.8
	add_child(light)
	return light


func apply_mood(mood_name: String) -> void:
	mood = mood_name
	var m: Dictionary = MOODS[mood_name]
	var g := func(key: String, value: Variant) -> void:
		globals[key] = value
		RenderingServer.global_shader_parameter_set("street_" + key, value)
	g.call("sky_zenith", m.zenith)
	g.call("sky_horizon", m.horizon)
	g.call("haze", m.haze)
	g.call("haze_density", m.haze_density)
	g.call("ambient_sky", m.amb_sky)
	g.call("ambient_ground", m.amb_ground)
	var to_sun: Vector3 = (m.sun_dir as Vector3).normalized()
	g.call("sun_dir", to_sun)
	g.call("sun_color", m.sun_color)
	g.call("moon_dir", to_sun)
	g.call("moon", m.moon)
	g.call("stars", m.stars)
	g.call("clouds", m.clouds)
	g.call("cloud_color", m.cloud_color)
	g.call("wet", m.wet)
	g.call("night", m.night)
	g.call("windows_lit", m.windows_lit)
	g.call("interior_light", m.interior)
	sun.light_color = m.sun_color
	sun.light_energy = m.sun_energy
	sun.visible = m.sun_energy > 0.0
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	for lamp in _lamps:
		lamp.light_energy = m.lamp
		lamp.visible = m.lamp > 0.0
	for light in _shop_lights:
		light.light_energy = m.shop
	for light in _neon_lights:
		light.light_energy = m.neon * 0.25
	_glow("Lamp", m.lamp_glow)
	_glow("Neon", m.neon)
	_glow("Signal", 6.0)
	_glow("Headlight", 0.0)
	_glow("Taillight", 0.0)
	if _moving_glows.has("Headlight"):
		_moving_glows.Headlight.set_shader_parameter("energy", m.head)
		_moving_glows.Taillight.set_shader_parameter("energy", maxf(m.head * 0.6, 0.6))
	if _leaves:
		_leaves.set_shader_parameter("wind", m.wind)
	for car in _cars:
		(car.light as SpotLight3D).visible = m.head > 0.0 and Quality.level >= Quality.Level.MEDIUM
	_populate(m.people, m.wet > 0.5)
	for sheet in _rain_sheets:
		sheet.visible = m.wet > 0.0
		(sheet.material_override as ShaderMaterial).set_shader_parameter("rain", m.wet)
	_apply_quality(Quality.level)


func _glow(mat_name: String, energy: float) -> void:
	if _glows.has(mat_name):
		(_glows[mat_name] as ShaderMaterial).set_shader_parameter("energy", energy)


func _apply_quality(level: int) -> void:
	var golden: bool = mood != "" and MOODS[mood].sun_shadow
	sun.shadow_enabled = golden and level >= Quality.Level.MEDIUM
	for light in _shop_lights + _neon_lights:
		light.visible = level >= Quality.Level.MEDIUM and light.light_energy > 0.0


func _process(delta: float) -> void:
	_time += delta
	RenderingServer.global_shader_parameter_set("street_time", fmod(_time, 3600.0))
	var main_state := _signal_state(0)
	RenderingServer.global_shader_parameter_set("street_signal_main", float(main_state))
	RenderingServer.global_shader_parameter_set("street_signal_cross", float(_signal_state(1)))
	_traffic(delta, main_state)
	_walk(delta)
	_birds(delta)


## 0 red, 1 amber, 2 green for the main street (road 0) or the cross street.
func _signal_state(road: int) -> int:
	var total := 0.0
	for s in CYCLE:
		total += s
	var t := fmod(_time + 8.0, total)
	var phase := 0
	while t >= CYCLE[phase]:
		t -= CYCLE[phase]
		phase += 1
	var mine := phase < 3 if road == 0 else phase >= 3
	if not mine:
		return 0
	return [2, 1, 0][phase % 3]


# --- traffic -------------------------------------------------------------------

func _traffic(delta: float, main_state: int) -> void:
	if _templates.is_empty():
		return
	var lanes: Array = layout.lanes
	for i in lanes.size():
		_next_car[i] -= delta
		if _next_car[i] <= 0.0:
			_spawn(i)
			_next_car[i] = _rng.randf_range(5.0, 16.0)
	var cross: Array = layout.cross
	for car in _cars:
		var lane: Dictionary = lanes[car.lane]
		var dir: float = lane.dir
		# Stop line: before the crossing, on the near side of the cross street.
		var stop_x: float = (cross[0] - 1.5) if dir > 0.0 else (cross[1] + 1.5)
		var front: float = car.x + dir * car.length * 0.5
		var target: float = car.cruise
		var to_stop: float = (stop_x - front) * dir
		if main_state != 2 and to_stop > 0.0 and to_stop < 30.0:
			target = minf(target, maxf(0.0, (to_stop - 0.5) * 0.9))
		# Keep back from the car in front.
		for other in _cars:
			if other == car or other.lane != car.lane:
				continue
			var gap: float = (other.x - car.x) * dir - (other.length + car.length) * 0.5
			if gap > 0.0 and gap < 25.0:
				target = minf(target, maxf(0.0, (gap - 2.5) * 0.8))
		var accel := 3.0 if target > car.speed else 7.0
		car.speed = move_toward(car.speed, target, accel * delta)
		car.x += dir * car.speed * delta
		(car.node as Node3D).position.x = car.x
	# Gone past the end of the street.
	for car in _cars.duplicate():
		var lane: Dictionary = lanes[car.lane]
		var xr: Array = lane.x
		if car.x < float(xr[0]) - 10.0 or car.x > float(xr[1]) + 10.0:
			(car.node as Node3D).queue_free()
			_cars.erase(car)


func _spawn(lane_index: int) -> void:
	var lane: Dictionary = layout.lanes[lane_index]
	var dir: float = lane.dir
	var xr: Array = lane.x
	var x: float = float(xr[0]) if dir > 0.0 else float(xr[1])
	# Not on top of a car that's waiting at the start.
	for car in _cars:
		if car.lane == lane_index and absf(car.x - x) < 12.0:
			return
	var template: MeshInstance3D = _templates[_rng.randi() % _templates.size()]
	var info: Dictionary = {}
	for c: Dictionary in layout.cars:
		if c.name == template.name:
			info = c
	var holder := Node3D.new()
	holder.name = "Car"
	var body := template.duplicate() as MeshInstance3D
	body.visible = true
	holder.add_child(body)
	holder.position = Vector3(x, 0.0, lane.z)
	holder.rotation.y = 0.0 if dir > 0.0 else PI
	var paints := [Color(0.75, 0.75, 0.74), Color(0.35, 0.37, 0.4), Color(0.04, 0.04, 0.05), Color(0.08, 0.12, 0.25),
		Color(0.5, 0.06, 0.05), Color(0.1, 0.2, 0.14), Color(0.95, 0.72, 0.1), Color(0.8, 0.8, 0.8)]
	var taxi: bool = info.get("taxi", false)
	body.set_instance_shader_parameter("paint", Color.WHITE if taxi else paints[_rng.randi() % paints.size()])
	# Headlights on the road ahead.
	var beam := SpotLight3D.new()
	beam.light_cull_mask = LAYER
	beam.light_color = Color(1.0, 0.92, 0.8)
	beam.light_energy = 6.0
	beam.spot_range = 22.0
	beam.spot_angle = 32.0
	beam.position = Vector3(float(info.get("length", 4.5)) * 0.5, -5.75, 0.0)
	beam.rotation = Vector3(-0.12, -PI / 2, 0.0)
	holder.add_child(beam)
	beam.visible = MOODS[mood].head > 0.0 and Quality.level >= Quality.Level.MEDIUM if mood != "" else false
	add_child(holder)
	_cars.append({"node": holder, "light": beam, "lane": lane_index, "x": x, "speed": 9.0,
		"cruise": _rng.randf_range(8.0, 12.0), "length": float(info.get("length", 4.5))})


# --- people --------------------------------------------------------------------

const SKINS := [Color(0.95, 0.78, 0.65), Color(0.85, 0.64, 0.5), Color(0.7, 0.5, 0.36), Color(0.52, 0.36, 0.25),
	Color(0.36, 0.24, 0.17), Color(0.92, 0.72, 0.55)]
const TOPS := [Color(0.12, 0.16, 0.3), Color(0.62, 0.45, 0.28), Color(0.07, 0.07, 0.08), Color(0.3, 0.33, 0.2),
	Color(0.42, 0.1, 0.12), Color(0.45, 0.45, 0.47), Color(0.8, 0.6, 0.2), Color(0.15, 0.4, 0.42), Color(0.8, 0.78, 0.72),
	Color(0.6, 0.2, 0.35)]
const BOTTOMS := [Color(0.16, 0.22, 0.35), Color(0.06, 0.06, 0.07), Color(0.3, 0.3, 0.32), Color(0.55, 0.47, 0.35),
	Color(0.2, 0.28, 0.45)]
const HAIRS := [Color(0.05, 0.04, 0.03), Color(0.2, 0.12, 0.07), Color(0.55, 0.4, 0.2), Color(0.6, 0.6, 0.6),
	Color(0.4, 0.15, 0.06), Color(0.85, 0.72, 0.45)]
const UMBRELLAS := [Color(0.08, 0.08, 0.09), Color(0.6, 0.08, 0.08), Color(0.1, 0.2, 0.5), Color(0.9, 0.75, 0.15),
	Color(0.2, 0.45, 0.3), Color(0.85, 0.85, 0.85)]


## Fills the sidewalks with `count` people (umbrellas up in the rain).
func _populate(count: int, rain: bool) -> void:
	for w in _walkers:
		(w.node as Node).queue_free()
	_walkers.clear()
	if _walker_templates.is_empty():
		return
	var lines: Array = layout.walk
	if Quality.level == Quality.Level.LOW:
		count = count / 2
	for i in count:
		# Two thirds on the far side, where they're easier to see.
		var line := 1 if i % 3 != 0 else 0
		var xr: Array = lines[line].x
		_spawn_walker(line, _rng.randf_range(float(xr[0]), float(xr[1])), rain)


func _spawn_walker(line: int, x: float, rain: bool) -> void:
	var lane: Dictionary = layout.walk[line]
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	var holder := Node3D.new()
	holder.name = "Walker"
	var body := _walker_templates[_rng.randi() % _walker_templates.size()].duplicate() as MeshInstance3D
	body.visible = true
	holder.add_child(body)
	var speed := _rng.randf_range(1.05, 1.55)
	if body.name.ends_with("kid"):
		speed *= 1.1
	body.set_instance_shader_parameter("skin", SKINS[_rng.randi() % SKINS.size()])
	body.set_instance_shader_parameter("top", TOPS[_rng.randi() % TOPS.size()])
	body.set_instance_shader_parameter("bottom", BOTTOMS[_rng.randi() % BOTTOMS.size()])
	body.set_instance_shader_parameter("shoes", Color(0.9, 0.9, 0.88) if _rng.randf() < 0.3 else Color(0.06, 0.05, 0.05))
	body.set_instance_shader_parameter("hair", HAIRS[_rng.randi() % HAIRS.size()])
	# A full stride cycle (two steps) covers about 1.4 m.
	body.set_instance_shader_parameter("step_rate", TAU * speed / 1.4)
	body.set_instance_shader_parameter("phase", _rng.randf() * TAU)
	if rain and _umbrella:
		var umbrella := _umbrella.duplicate() as MeshInstance3D
		umbrella.visible = true
		umbrella.position = Vector3(0.1, 1.2, -0.1)
		umbrella.rotation.x = 0.12
		umbrella.set_instance_shader_parameter("paint", UMBRELLAS[_rng.randi() % UMBRELLAS.size()])
		holder.add_child(umbrella)
	holder.position = Vector3(x, float(layout.walk_y), float(lane.z) + _rng.randf_range(-0.25, 0.25))
	holder.rotation.y = 0.0 if dir > 0.0 else PI
	add_child(holder)
	_walkers.append({"node": holder, "dir": dir, "speed": speed, "line": line, "x": x})


func _walk(delta: float) -> void:
	for w in _walkers:
		w.x += w.dir * w.speed * delta
		var node: Node3D = w.node
		node.position.x = w.x
		var xr: Array = layout.walk[w.line].x
		# Off one end: come back on at the other, as someone new.
		if w.x < float(xr[0]) - 2.0 or w.x > float(xr[1]) + 2.0:
			var rain: bool = mood != "" and MOODS[mood].wet > 0.5
			node.queue_free()
			_walkers.erase(w)
			_spawn_walker(w.line, float(xr[0]) if w.dir > 0.0 else float(xr[1]), rain)
			return


# --- birds ---------------------------------------------------------------------

## Now and then (golden hour) a flock of pigeons wheels across the sky over
## the rooftops, left to right or back, each bird weaving round the flock.
func _birds(delta: float) -> void:
	if _bird == null or mood == "":
		return
	if _flock == null:
		if not MOODS[mood].birds:
			return
		_next_flock -= delta
		if _next_flock > 0.0:
			return
		_next_flock = _rng.randf_range(25.0, 50.0)
		_flock = Node3D.new()
		_flock.name = "Flock"
		add_child(_flock)
		_flock_t = 0.0
		var dir := 1.0 if _rng.randf() < 0.5 else -1.0
		_flock.set_meta("dir", dir)
		_flock.set_meta("z", _rng.randf_range(-24.0, -45.0))
		_flock.set_meta("y", _rng.randf_range(4.0, 11.0))
		for i in _rng.randi_range(9, 16):
			var b := _bird.duplicate() as MeshInstance3D
			b.visible = true
			b.set_instance_shader_parameter("flap_phase", _rng.randf() * TAU)
			b.set_instance_shader_parameter("flap_rate", _rng.randf_range(12.0, 16.0))
			b.set_meta("offset", Vector3(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-1.5, 1.5), _rng.randf_range(-3.0, 3.0)))
			b.set_meta("wobble", _rng.randf() * TAU)
			_flock.add_child(b)
		return
	_flock_t += delta
	var dir: float = _flock.get_meta("dir")
	# Across ~140 m in ~12 s, rising and dipping in a long curve.
	var x := dir * (-70.0 + _flock_t * 11.0)
	var y: float = _flock.get_meta("y") + sin(_flock_t * 0.6) * 2.0
	var z: float = _flock.get_meta("z") + sin(_flock_t * 0.35) * 6.0
	var centre := Vector3(x, y, z)
	var heading := Vector3(dir * 11.0, cos(_flock_t * 0.6) * 1.2, cos(_flock_t * 0.35) * 2.1).normalized()
	for b: MeshInstance3D in _flock.get_children():
		var o: Vector3 = b.get_meta("offset")
		var w: float = b.get_meta("wobble")
		var wobble := Vector3(sin(_flock_t * 1.3 + w) * 1.2, sin(_flock_t * 1.7 + w * 2.0) * 0.6, cos(_flock_t * 1.1 + w) * 1.0)
		b.position = centre + o + wobble
		b.basis = Basis.looking_at(heading, Vector3.UP) * Basis(Vector3.UP, PI / 2)  # the model faces +x
	if absf(x) > 75.0:
		_flock.queue_free()
		_flock = null
