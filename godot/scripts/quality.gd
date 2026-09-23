extends Node
## Graphics quality presets (autoload "Quality").
##
## LOW     integrated GPUs: no caustics, no screen-read refraction, no SSAO or
##         glow, 0.8 render scale, no MSAA, fewer particles.
## MEDIUM  caustics, refraction, glow, 2x MSAA.
## HIGH    adds SSAO, softer shadows, 4x MSAA and denser particles.
##
## The setting is "auto" until the player picks one: auto chooses LOW on
## integrated or software GPUs and HIGH on dedicated ones.

signal changed(level: Level)

enum Level { LOW, MEDIUM, HIGH }

const NAMES := ["Low", "Medium", "High"]
const CAUSTICS := preload("res://shaders/caustics.gdshader")

var level := Level.MEDIUM
## "auto" or one of NAMES, lowercased, as stored in settings.
var setting := "auto"

var _caustic_hosts: Array[Material] = []
var _caustic_pass: ShaderMaterial
var _environment: Environment


func _ready() -> void:
	_caustic_pass = ShaderMaterial.new()
	_caustic_pass.shader = CAUSTICS
	setting = Settings.get_value("graphics", "quality", "auto")
	level = _resolve(setting)


## Level for a setting: a named level, or "auto" by GPU type.
func _resolve(value: String) -> Level:
	var i := ["low", "medium", "high"].find(value)
	if i >= 0:
		return i as Level
	return auto_level()


static func auto_level() -> Level:
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return Level.HIGH
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_CPU:
			return Level.LOW
		_:
			return Level.MEDIUM


func set_setting(value: String) -> void:
	setting = value
	Settings.set_value("graphics", "quality", value)
	var new_level := _resolve(value)
	if new_level != level:
		level = new_level
		_apply()


## Called once the scene exists: the environment whose effects we control.
func attach(environment: Environment) -> void:
	_environment = environment
	_apply()


## Adds the caustics pass to `material` whenever the level allows it.
func add_caustics(material: Material) -> void:
	if material == null or material in _caustic_hosts:
		return
	_caustic_hosts.append(material)
	material.next_pass = _caustic_pass if level >= Level.MEDIUM else null


func particle_scale() -> float:
	return [0.4, 0.75, 1.0][level]


func _apply() -> void:
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][level]
	vp.scaling_3d_scale = 0.8 if level == Level.LOW else 1.0
	vp.positional_shadow_atlas_size = [1024, 2048, 4096][level]
	if _environment:
		_environment.ssao_enabled = level == Level.HIGH
		_environment.ssao_intensity = 1.2
		_environment.ssao_radius = 0.3
		_environment.glow_enabled = level >= Level.MEDIUM
	for m in _caustic_hosts:
		m.next_pass = _caustic_pass if level >= Level.MEDIUM else null
	RenderingServer.global_shader_parameter_set("caustics_strength", 1.0 if level >= Level.MEDIUM else 0.0)
	changed.emit(level)
