class_name FlashCard
extends Node3D
## A laminated flash card showing one controller prompt. Cards always face the
## front glass (+Z in tank space). The trigger zone and pressing logic live in
## CardSystem; this node is just the physical card and its highlight.

var input_id: String
var size: Vector2
var active := false:
	set = set_active

var _border_mat: StandardMaterial3D
var _face: Node3D
var _zone_debug: MeshInstance3D


func _init(p_input_id: String, p_size: Vector2) -> void:
	input_id = p_input_id
	size = p_size
	name = "Card_" + input_id


func _ready() -> void:
	var info: Dictionary = CardSystem.INPUTS[input_id]
	var color: Color = info.color

	_face = Node3D.new()
	add_child(_face)

	_border_mat = StandardMaterial3D.new()
	_border_mat.albedo_color = color.darkened(0.2)
	_border_mat.emission_enabled = true
	_border_mat.emission = color
	_border_mat.emission_energy_multiplier = 0.0
	_add_box(_face, Vector3(size.x + 0.008, size.y + 0.008, 0.002), Vector3(0, 0, -0.001), _border_mat)

	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.96, 0.95, 0.9)
	paper.roughness = 0.25 # laminated
	_add_box(_face, Vector3(size.x, size.y, 0.003), Vector3.ZERO, paper)

	var badge_mat := StandardMaterial3D.new()
	badge_mat.albedo_color = color
	badge_mat.roughness = 0.4
	var badge := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.024
	disc.bottom_radius = 0.024
	disc.height = 0.002
	badge.mesh = disc
	badge.material_override = badge_mat
	badge.rotation.x = PI / 2
	badge.position = Vector3(0, 0.006, 0.002)
	_face.add_child(badge)

	if info.has("arrow"):
		_add_arrow(_face, info.arrow, Vector3(0, 0.006, 0.0035))
	else:
		var glyph := _label(info.label, 64 if info.label.length() <= 2 else 36, Color.WHITE)
		glyph.position = Vector3(0, 0.006, 0.0035)
		_face.add_child(glyph)

	if info.has("caption"):
		var caption := _label(info.caption, 22, Color(0.2, 0.2, 0.22))
		caption.outline_size = 0
		caption.position = Vector3(0, -size.y / 2 + 0.01, 0.002)
		_face.add_child(caption)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.006)
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	if _face == null:
		return
	_border_mat.emission_energy_multiplier = 3.0 if active else 0.0
	_face.scale = Vector3.ONE * (1.08 if active else 1.0)


## Shows the card's trigger zone as a translucent box (F3).
func show_zone(zone: AABB, visible_: bool) -> void:
	if _zone_debug == null:
		_zone_debug = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(CardSystem.INPUTS[input_id].color, 0.12)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_zone_debug.material_override = mat
		_zone_debug.mesh = BoxMesh.new()
		add_child(_zone_debug)
	(_zone_debug.mesh as BoxMesh).size = zone.size
	_zone_debug.position = zone.get_center() - position
	_zone_debug.visible = visible_


func _add_box(parent: Node3D, box_size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _add_arrow(parent: Node3D, dir: Vector2, pos: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	var arrow := Node3D.new()
	arrow.position = pos
	# `dir` is y-up; the arrow mesh points along +Y before rotating about the card normal.
	arrow.rotation.z = atan2(-dir.x, dir.y)
	parent.add_child(arrow)
	var head := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.026, 0.016, 0.002)
	head.mesh = prism
	head.material_override = mat
	head.position = Vector3(0, 0.007, 0)
	arrow.add_child(head)
	_add_box(arrow, Vector3(0.009, 0.016, 0.002), Vector3(0, -0.008, 0), mat)


func _label(text: String, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.0004
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.5)
	label.outline_size = 6
	label.double_sided = false
	return label
