class_name RoomMoods
extends Node
## Puts the bedroom in a mood (the Mood autoload picks which): the baked
## lightmap, the view out of the window, rain on the glass, how brightly the
## lamps, LEDs and screens glow, and the live lights that light the fish, the
## tank and its decor (which aren't in the bake).
##
## Keep MOODS in step with art/models/room/moods.py, which bakes the same
## lamps and glows into the room.

const MOODS := {
	"night": {
		"exposure": 1.0, "view": 1.0, "rain": 0.0,
		"glow": {"GlowWarm": 3.0, "GlowRGB": 4.0, "GlowFairy": 3.0, "GlowTally": 3.0, "GlowChat": 1.1,
			"GlowRing": 0.0, "GlowCeiling": 0.0},
		"rgb": Color(0.62, 0.3, 1.0),
		"ambient": [Color(0.42, 0.45, 0.7), 0.22],
		"window": [Color(0.55, 0.65, 1.0), 0.12, Vector3(0.0, -0.5, 1.0)],
		"lamps": 0.9, "fairy": 0.35, "accent": 0.9, "tank": 1.7, "screen": 0.6,
	},
	"rainy": {
		"exposure": 1.0, "view": 0.9, "rain": 1.0,
		"glow": {"GlowWarm": 2.6, "GlowRGB": 1.4, "GlowFairy": 3.0, "GlowTally": 3.0, "GlowChat": 0.9,
			"GlowRing": 0.0, "GlowCeiling": 0.0},
		"rgb": Color(0.3, 0.7, 1.0),
		"ambient": [Color(0.6, 0.66, 0.78), 0.35],
		"window": [Color(0.7, 0.78, 0.92), 0.35, Vector3(0.0, -0.4, 1.0)],
		"lamps": 0.9, "fairy": 0.35, "accent": 0.35, "tank": 1.4, "screen": 0.45,
	},
	"golden": {
		"exposure": 1.25, "view": 1.0, "rain": 0.0,
		"glow": {"GlowWarm": 0.0, "GlowRGB": 0.4, "GlowFairy": 0.6, "GlowTally": 3.0, "GlowChat": 0.6,
			"GlowRing": 0.0, "GlowCeiling": 0.0},
		"rgb": Color(1.0, 0.5, 0.3),
		"ambient": [Color(1.0, 0.82, 0.66), 0.35],
		"window": [Color(1.0, 0.72, 0.45), 1.6, Vector3(-0.3, -0.75, 1.0)],
		"lamps": 0.0, "fairy": 0.1, "accent": 0.15, "tank": 0.9, "screen": 0.35,
	},
}

const GLOW_COLORS := {
	"GlowWarm": Color(1.0, 0.8, 0.55),
	"GlowCeiling": Color(1.0, 0.95, 0.85),
	"GlowFairy": Color(1.0, 0.82, 0.5),
	"GlowTally": Color(1.0, 0.1, 0.1),
	"GlowRing": Color(1.0, 0.98, 0.95),
}

var environment: Environment
## Every converted room material, by its Blender name.
var materials := {}
var view_material: ShaderMaterial
var glass_material: ShaderMaterial
var tank_light: Light3D
var screen_light: Light3D
var window_light: DirectionalLight3D
var lamps: Array[OmniLight3D] = []
var fairy_light: OmniLight3D
var accent_light: OmniLight3D

## The webcam's tally LED (lit while streaming).
var webcam_tally: MeshInstance3D
## Whether a stream is running: the room camera's and the webcam's tally
## lights say so (there's no on-screen HUD).
var live := false:
	set = set_live

var mood := ""
var _lightmaps := {}
var _views := {}


func _ready() -> void:
	apply(Mood.current)
	Mood.changed.connect(apply)
	Quality.changed.connect(func(_level: int) -> void: _shadows())


func apply(mood_name: String) -> void:
	mood = mood_name
	var m: Dictionary = MOODS[mood_name]
	var lightmap := _lightmap(mood_name)
	for mat: ShaderMaterial in materials.values():
		mat.set_shader_parameter("lightmap", lightmap)
		mat.set_shader_parameter("exposure", m.exposure)
	for mat_name: String in m.glow:
		var mat: ShaderMaterial = materials.get(mat_name)
		if mat == null:
			continue
		if mat_name != "GlowChat":
			mat.set_shader_parameter("emission_color", GLOW_COLORS.get(mat_name, Color.WHITE))
		mat.set_shader_parameter("emission_energy", m.glow[mat_name])
	_tally()
	if materials.has("GlowRGB"):
		materials.GlowRGB.set_shader_parameter("emission_color", m.rgb)
		materials.GlowRGB.set_shader_parameter("albedo", m.rgb)

	if view_material:
		view_material.set_shader_parameter("view", _view(mood_name))
		view_material.set_shader_parameter("energy", m.view)
	if glass_material:
		glass_material.set_shader_parameter("rain", m.rain)

	if environment:
		environment.ambient_light_color = m.ambient[0]
		environment.ambient_light_energy = m.ambient[1]
	if window_light:
		window_light.light_color = m.window[0]
		window_light.light_energy = m.window[1]
		var dir: Vector3 = (m.window[2] as Vector3).normalized()
		window_light.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	for lamp in lamps:
		lamp.light_energy = m.lamps
		lamp.visible = m.lamps > 0.0
	if fairy_light:
		fairy_light.light_energy = m.fairy
	if accent_light:
		accent_light.light_color = m.rgb
		accent_light.light_energy = m.accent
	if tank_light:
		tank_light.light_energy = m.tank
	if screen_light:
		screen_light.light_energy = m.screen
	_shadows()


func set_live(value: bool) -> void:
	if value == live:
		return
	live = value
	_tally()


func _tally() -> void:
	var tally: ShaderMaterial = materials.get("GlowTally")
	if tally and mood != "":
		tally.set_shader_parameter("emission_energy", MOODS[mood].glow.GlowTally if live else 0.0)
	if webcam_tally:
		webcam_tally.visible = live


## Only the golden hour's sun casts shadows (through the window frame), and
## only when the graphics level can afford it.
func _shadows() -> void:
	if window_light:
		window_light.shadow_enabled = mood == "golden" and Quality.level >= Quality.Level.MEDIUM


func _lightmap(mood_name: String) -> Texture2D:
	if not _lightmaps.has(mood_name):
		var path := "res://art/room/lightmap_%s.exr" % mood_name
		if ResourceLoader.exists(path):
			_lightmaps[mood_name] = load(path)
		else:
			# Not baked yet (ART_BAKE=none): flat, dim light.
			var img := Image.create(4, 4, false, Image.FORMAT_RGBH)
			img.fill(Color(0.35, 0.35, 0.4))
			_lightmaps[mood_name] = ImageTexture.create_from_image(img)
	return _lightmaps[mood_name]


func _view(mood_name: String) -> Texture2D:
	if not _views.has(mood_name):
		_views[mood_name] = load("res://art/room/view_%s.png" % mood_name)
	return _views[mood_name]
