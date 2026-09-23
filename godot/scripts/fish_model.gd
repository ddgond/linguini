class_name FishModel
extends Node3D
## Greybox goldfish built from primitives, animated from the Fish body state:
## tail and body sway with the tail beat, pectoral fins flutter.

const LENGTH := 0.09

var fish: Fish

var _body: MeshInstance3D
var _tail: Node3D
var _fins: Array[Node3D] = []


func _init(p_fish: Fish) -> void:
	fish = p_fish


func _ready() -> void:
	var orange := _material(Color(1.0, 0.45, 0.08), 0.35)
	var fin_mat := _material(Color(1.0, 0.62, 0.25, 0.8), 0.5)
	fin_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_body = MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.02
	body_mesh.height = 0.04
	_body.mesh = body_mesh
	_body.scale = Vector3(0.8, 1.1, 1.6)
	_body.material_override = orange
	add_child(_body)

	# Tail hangs off a pivot at the back of the body so it can swing.
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0, 0.028)
	add_child(_tail)
	var tail := MeshInstance3D.new()
	var tail_mesh := PrismMesh.new()
	tail_mesh.size = Vector3(0.045, 0.035, 0.003)
	tail.mesh = tail_mesh
	tail.material_override = fin_mat
	tail.rotation = Vector3(0, PI / 2, -PI / 2)
	tail.position = Vector3(0, 0, 0.016)
	_tail.add_child(tail)

	var dorsal := MeshInstance3D.new()
	var dorsal_mesh := PrismMesh.new()
	dorsal_mesh.size = Vector3(0.03, 0.018, 0.002)
	dorsal_mesh.left_to_right = 0.2
	dorsal.mesh = dorsal_mesh
	dorsal.material_override = fin_mat
	dorsal.rotation = Vector3(0, PI / 2, 0)
	dorsal.position = Vector3(0, 0.026, 0.004)
	add_child(dorsal)

	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.014 * side, -0.008, -0.008)
		add_child(pivot)
		var fin := MeshInstance3D.new()
		var fin_mesh := QuadMesh.new()
		fin_mesh.size = Vector2(0.018, 0.01)
		fin.mesh = fin_mesh
		fin.material_override = fin_mat
		fin.position = Vector3(0.008 * side, 0, 0.004)
		fin.rotation = Vector3(PI / 2, 0, 0)
		pivot.add_child(fin)
		pivot.set_meta("side", side)
		_fins.append(pivot)

		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.0055
		eye_mesh.height = 0.011
		eye.mesh = eye_mesh
		eye.material_override = _material(Color(0.95, 0.95, 0.95), 0.2)
		eye.position = Vector3(0.013 * side, 0.006, -0.018)
		add_child(eye)
		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = 0.003
		pupil_mesh.height = 0.006
		pupil.mesh = pupil_mesh
		pupil.material_override = _material(Color(0.02, 0.02, 0.02), 0.1)
		pupil.position = Vector3(0.0035 * side, 0.0005, -0.002)
		eye.add_child(pupil)


func _process(_delta: float) -> void:
	if fish == null:
		return
	var swing := sin(fish.tail_phase)
	var amplitude := 0.25 + 0.55 * fish.effort
	_tail.rotation.y = swing * amplitude
	# The body counter-sways a little against the tail.
	rotation.y = -swing * amplitude * 0.12
	for pivot in _fins:
		var side: float = pivot.get_meta("side")
		pivot.rotation.z = side * (0.3 + 0.35 * sin(fish.fin_phase + side))


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m
