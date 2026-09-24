class_name FlashCard
extends Node3D
## A laminated flash card showing what it presses. Cards always face the front
## glass (+Z in tank space). The trigger zone and pressing logic live in
## CardSystem; this node is just the physical card and its highlight.
##
## Cards are matte laminated classroom flash cards: a rounded paper slab
## with a printed face (CardFace). While held, the lamination's edge lights
## in the card's colour; a sequence card fills a bar along its bottom as its
## macro plays. Toggle cards say TOGGLE, and stay lit while they're switched on.

const SEQUENCE_COLOR := Color(0.1, 0.62, 0.6)
const SELECTED_COLOR := Color(1.0, 0.85, 0.2)
const THICKNESS := 0.003
const CORNER := 0.007
const CARD_SHADER := preload("res://shaders/card.gdshader")

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
## True while the card is a toggle that's switched on.
var latched := false:
	set = set_latched
## How far through its sequence the card is (0..1), or -1 when not playing.
var progress := -1.0:
	set = set_progress

var _face_mat: ShaderMaterial
var _face: Node3D
var _selected := false
var _pulse := 0.0
var _zone_debug: MeshInstance3D


func _init(p_binding: CardBinding, p_size: Vector2) -> void:
	binding = p_binding
	size = p_size
	name = "Card_" + "_".join(binding.all_inputs())


func card_color() -> Color:
	if binding.kind == CardBinding.Kind.SEQUENCE:
		return SEQUENCE_COLOR
	var ids := binding.all_inputs()
	if ids.size() == 1:
		return Glyphs.color(ids[0])
	return CardSystem.INPUTS[ids[0]].color


func _ready() -> void:
	_face = Node3D.new()
	add_child(_face)

	_face_mat = ShaderMaterial.new()
	_face_mat.shader = CARD_SHADER
	_face_mat.set_shader_parameter("size", size)
	_face_mat.set_shader_parameter("radius", CORNER)
	var back := StandardMaterial3D.new()
	back.albedo_color = Color(0.93, 0.92, 0.88)
	back.roughness = 0.7
	var slab := MeshInstance3D.new()
	slab.name = "Card"
	slab.mesh = card_mesh(size, CORNER, THICKNESS)
	slab.set_surface_override_material(0, _face_mat)
	slab.set_surface_override_material(1, back)
	_face.add_child(slab)
	Quality.add_caustics(_face_mat)
	Quality.add_caustics(back)
	_update_highlight()
	set_process(false)
	_request_face()
	Glyphs.changed.connect(func(_set: String) -> void: _request_face())

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.006)
	shape.shape = box
	body.add_child(shape)
	# Layer 2 lets the tank editor pick cards without hitting the glass.
	body.collision_layer = 1 | 2
	add_child(body)


func _request_face() -> void:
	var mat := _face_mat
	CardFace.request(binding, card_color(), size, func(tex: Texture2D) -> void:
		mat.set_shader_parameter("face", tex))


func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	if _face != null:
		_update_highlight()
		if value:
			# A soft pulse of the edge light as it presses.
			_pulse = 1.0
			set_process(true)


func _process(delta: float) -> void:
	_pulse = maxf(_pulse - delta / 0.35, 0.0)
	_update_highlight()
	if _pulse <= 0.0:
		set_process(false)


func set_playing(value: bool) -> void:
	if value == playing:
		return
	playing = value
	if _face != null:
		_update_highlight()


func set_latched(value: bool) -> void:
	if value == latched:
		return
	latched = value
	if _face != null:
		_update_highlight()


func set_progress(value: float) -> void:
	progress = value
	if _face_mat:
		_face_mat.set_shader_parameter("progress", value)


func _update_highlight() -> void:
	var lit := active or playing or latched
	_face_mat.set_shader_parameter("edge_color", SELECTED_COLOR if _selected else card_color())
	var glow := 1.0 if lit else (0.6 if _selected else 0.0)
	_face_mat.set_shader_parameter("glow", glow + 1.2 * _pulse * _pulse)


## Selection outline for the tank editor.
func set_selected(value: bool) -> void:
	_selected = value
	if _face != null:
		_update_highlight()


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


## For a hold or toggle card of only stick directions (one stick) or only
## D-pad directions, the direction they add up to; otherwise zero.
static func combined_arrow(b: CardBinding) -> Vector2:
	var ids := b.all_inputs()
	var sequence := b.kind == CardBinding.Kind.SEQUENCE
	if sequence or ids.size() < 2:
		return CardSystem.INPUTS[ids[0]].get("arrow", Vector2.ZERO) if ids.size() == 1 and not sequence else Vector2.ZERO
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


## A rounded-corner slab facing +Z: surface 0 is the printed front (UVs span
## the face), surface 1 the back and edges.
static func card_mesh(card_size: Vector2, corner: float, thickness: float) -> ArrayMesh:
	var outline := PackedVector2Array()
	var half := card_size / 2.0 - Vector2(corner, corner)
	for q in 4:
		var c := Vector2(half.x * (1 if q in [0, 3] else -1), half.y * (1 if q < 2 else -1))
		for i in 7:
			var a := PI / 2.0 * q + PI / 2.0 * i / 6.0
			outline.append(c + Vector2(cos(a), sin(a)) * corner)
	var z := thickness / 2.0
	var mesh := ArrayMesh.new()
	for side in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := outline.size()
		if side == 0:
			for i in n:
				var p0 := outline[i]
				var p1 := outline[(i + 1) % n]
				# Godot's front faces wind clockwise.
				for p: Vector2 in [Vector2.ZERO, p1, p0]:
					st.set_normal(Vector3.BACK)
					st.set_uv(Vector2(p.x / card_size.x + 0.5, 0.5 - p.y / card_size.y))
					st.add_vertex(Vector3(p.x, p.y, z))
		else:
			for i in n:
				var p0 := outline[i]
				var p1 := outline[(i + 1) % n]
				for p: Vector2 in [Vector2.ZERO, p0, p1]:
					st.set_normal(Vector3.FORWARD)
					st.add_vertex(Vector3(p.x, p.y, -z))
				var out := Vector3((p0 + p1).x, (p0 + p1).y, 0).normalized()
				for v: Vector3 in [Vector3(p0.x, p0.y, z), Vector3(p1.x, p1.y, -z), Vector3(p0.x, p0.y, -z),
						Vector3(p0.x, p0.y, z), Vector3(p1.x, p1.y, z), Vector3(p1.x, p1.y, -z)]:
					st.set_normal(out)
					st.add_vertex(v)
		st.commit(mesh)
	return mesh
