class_name FishModel
extends Node3D
## Linguini's fantail (res://art/fish.glb, made by art/models/fish.py), animated
## by vertex shaders from the Fish body state: the body bends in a travelling
## wave with the tail beat, the fins ripple, and the tail trails out of turns.

const MODEL := preload("res://art/fish.glb")
const BODY_SHADER := preload("res://shaders/fish_body.gdshader")
const FIN_SHADER := preload("res://shaders/fish_fin.gdshader")

## The colourings a fish can have (fish_variety.gdshaderinc), by number, named
## for pasta, all in -i like Linguini: Tortellini (as painted), Fusilli
## (calico, as tricolour fusilli), Gnocchi (pale, with a red cap) and Ravioli
## (black and orange).
const VARIETIES := ["Tortellini", "Fusilli", "Gnocchi", "Ravioli"]

var fish: Fish
var mesh_instance: MeshInstance3D
## Which of VARIETIES this fish wears.
var variety := 0:
	set(value):
		variety = value
		for mat in _materials:
			if mat.get_meta("recolour", false):
				mat.set_shader_parameter("variety", variety)
var _materials: Array[ShaderMaterial] = []


func _init(p_fish: Fish) -> void:
	fish = p_fish


func _ready() -> void:
	var scene := MODEL.instantiate()
	add_child(scene)
	mesh_instance = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh := mesh_instance.mesh
	for i in mesh.get_surface_count():
		var imported := mesh.surface_get_material(i)
		var mat := ShaderMaterial.new()
		mat.set_meta("recolour", imported == null or imported.resource_name != "FishEye")
		match imported.resource_name if imported else "":
			"FishFin":
				mat.shader = FIN_SHADER
			"FishEye":
				mat.shader = BODY_SHADER
				mat.set_shader_parameter("scale_strength", 0.0)
				mat.set_shader_parameter("roughness", 0.06)
				mat.set_shader_parameter("clearcoat", 1.0)
			_:
				mat.shader = BODY_SHADER
				if imported is BaseMaterial3D and imported.albedo_texture:
					mat.set_shader_parameter("scales", imported.albedo_texture)
				else:
					mat.set_shader_parameter("scale_strength", 0.0)
		mesh_instance.set_surface_override_material(i, mat)
		_materials.append(mat)
		if mat.get_meta("recolour"):
			mat.set_shader_parameter("variety", variety)


## The model's bounds in the fish's own space (for the tank cam's box).
func local_aabb() -> AABB:
	if mesh_instance == null:
		return AABB(Vector3(-0.018, -0.024, -0.045), Vector3(0.036, 0.048, 0.09))
	return mesh_instance.get_aabb()


func _process(_delta: float) -> void:
	if fish == null:
		return
	for mat in _materials:
		mat.set_shader_parameter("tail_phase", fish.tail_phase)
		mat.set_shader_parameter("fin_phase", fish.fin_phase)
		mat.set_shader_parameter("effort", fish.effort)
		mat.set_shader_parameter("turn", fish.yaw_rate)
		mat.set_shader_parameter("screen_fade", fish.screen_fade)
