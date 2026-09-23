class_name FlashCard
extends Node3D
## A laminated flash card showing what it presses. Cards always face the front
## glass (+Z in tank space). The trigger zone and pressing logic live in
## CardSystem; this node is just the physical card and its highlight.
##
## Faces: one input shows its button or arrow; a stick or D-pad diagonal shows
## one combined arrow; other combos and sequences show their name.

const SEQUENCE_COLOR := Color(0.1, 0.62, 0.6)

var binding: CardBinding
## The card's first input; enough to identify single-input cards.
var input_id: String:
	get:
		return binding.all_inputs()[0]
var size: Vector2
var active := false:
	set = set_active
## True while the card's sequence is playing.
var playing := false:
	set = set_playing

var _border_mat: StandardMaterial3D
var _face: Node3D
var _zone_debug: MeshInstance3D


func _init(p_binding: CardBinding, p_size: Vector2) -> void:
	binding = p_binding
	size = p_size
	name = "Card_" + "_".join(binding.all_inputs())


func card_color() -> Color:
	if binding.kind == CardBinding.Kind.SEQUENCE:
		return SEQUENCE_COLOR
	return CardSystem.INPUTS[input_id].color


func _ready() -> void:
	var ids := binding.all_inputs()
	var info: Dictionary = CardSystem.INPUTS[ids[0]]
	var color := card_color()

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

	var arrow := _combined_arrow(ids)
	var single := binding.kind == CardBinding.Kind.HOLD and ids.size() == 1
	var caption_text: String = info.get("caption", "")
	if single or arrow != Vector2.ZERO:
		_add_badge(color)
		if arrow != Vector2.ZERO:
			_add_arrow(_face, arrow, Vector3(0, 0.006, 0.0035))
		else:
			var glyph := _label(info.label, 64 if info.label.length() <= 2 else 36, Color.WHITE)
			glyph.position = Vector3(0, 0.006, 0.0035)
			_face.add_child(glyph)
	else:
		var text := binding.display_name()
		var name_label := _label(text, 46 if text.length() <= 7 else 36, color.darkened(0.35))
		name_label.outline_size = 0
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.width = size.x * 0.92 / name_label.pixel_size
		name_label.position = Vector3(0, 0.005, 0.0035)
		_face.add_child(name_label)
		if binding.kind == CardBinding.Kind.SEQUENCE:
			caption_text = "SEQUENCE · %.1f s" % (binding.duration_ms() / 1000.0)
		else:
			caption_text = "COMBO"

	if caption_text != "":
		var caption := _label(caption_text, 22, Color(0.2, 0.2, 0.22))
		caption.outline_size = 0
		caption.position = Vector3(0, -size.y / 2 + 0.01, 0.002)
		_face.add_child(caption)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.006)
	shape.shape = box
	body.add_child(shape)
	# Layer 2 lets the tank editor pick cards without hitting the glass.
	body.collision_layer = 1 | 2
	add_child(body)


func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	if _face == null:
		return
	_update_highlight()


func set_playing(value: bool) -> void:
	if value == playing:
		return
	playing = value
	if _face != null:
		_update_highlight()


func _update_highlight() -> void:
	_border_mat.emission_energy_multiplier = 3.0 if (active or playing) else 0.0
	_face.scale = Vector3.ONE * (1.08 if active else 1.0)


## Selection outline for the tank editor.
func set_selected(value: bool) -> void:
	if _face == null:
		return
	_border_mat.albedo_color = Color(1.0, 0.85, 0.2) if value else card_color().darkened(0.2)
	_border_mat.emission = Color(1.0, 0.85, 0.2) if value else card_color()
	_border_mat.emission_energy_multiplier = 1.5 if value else (3.0 if (active or playing) else 0.0)


## Shows the card's trigger zone as a translucent box (F3).
func show_zone(zone: AABB, visible_: bool) -> void:
	if _zone_debug == null:
		_zone_debug = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(card_color(), 0.12)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_zone_debug.material_override = mat
		_zone_debug.mesh = BoxMesh.new()
		add_child(_zone_debug)
	(_zone_debug.mesh as BoxMesh).size = zone.size
	_zone_debug.position = zone.get_center() - position
	_zone_debug.visible = visible_


## For a hold card of only stick directions (one stick) or only D-pad
## directions, the direction they add up to; otherwise zero.
func _combined_arrow(ids: PackedStringArray) -> Vector2:
	if binding.kind != CardBinding.Kind.HOLD or ids.size() < 2:
		return CardSystem.INPUTS[ids[0]].get("arrow", Vector2.ZERO) if ids.size() == 1 else Vector2.ZERO
	var group := ""
	var sum := Vector2.ZERO
	for id in ids:
		var info: Dictionary = CardSystem.INPUTS[id]
		if not info.has("arrow"):
			return Vector2.ZERO
		var g: String = info.get("stick", "dpad")
		if group != "" and g != group:
			return Vector2.ZERO
		group = g
		sum += info.arrow
	return sum.normalized() if sum.length() > 0.01 else Vector2.ZERO


func _add_badge(color: Color) -> void:
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
