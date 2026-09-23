class_name TankEditor
extends Node
## In-game editor for the tank: place, move, rebind, duplicate and delete
## cards (combos, toggles and sequences too), arrange decor, and save or load
## named presets holding both.
##
## Mouse: click a card or a piece of decor to select it and drag to move it.
## Cards move parallel to the glass (Shift+drag: nearer or further). Decor
## moves along what it's anchored to: the gravel, the water surface, the rims,
## or anywhere in the water (moss balls; Shift+drag for depth). Right-drag
## orbits the camera; the wheel zooms. Esc or Done leaves the editor.
##
## Cards always face the front glass, so only decor rotates.

signal closed
signal preset_changed(preset_name: String)

const PANEL_WIDTH := 440
const STEP_MS := 10

var cards: CardSystem
var decor: TankDecor
## The water volume in the tank's local space; cards are kept inside it.
var water_local: AABB
## Point the camera orbits, in global space.
var focus := Vector3.ZERO

var preset_name := LayoutPresets.DEFAULT
var dirty := false
var selected: FlashCard
var selected_decor: DecorPiece

var camera: Camera3D
var _orbit_yaw := 0.0
var _orbit_pitch := 0.12
var _distance := 1.45
var _orbiting := false
var _dragging := false
var _drag_offset := Vector3.ZERO
var _confirm := "" ## action waiting for a second click

var _layer: CanvasLayer
var _preset_list: OptionButton
var _title: Label
var _status: Label
var _save_as_name: LineEdit
var _card_box: VBoxContainer
var _decor_choice: OptionButton


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.02
	add_child(camera)

	_layer = CanvasLayer.new()
	_layer.layer = 5
	_layer.visible = false
	add_child(_layer)
	_build_panel()
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _layer.visible


func open() -> void:
	_layer.visible = true
	set_process_unhandled_input(true)
	camera.make_current()
	_update_camera()
	cards.set_zones_visible(true)
	_refresh_presets()
	_select(null)


func close() -> void:
	_select(null)
	_dragging = false
	_orbiting = false
	_layer.visible = false
	set_process_unhandled_input(false)
	cards.set_zones_visible(false)
	closed.emit()


## Loads a preset by name into the tank. Returns false if it doesn't exist.
func load_preset(p_name: String) -> bool:
	var data := LayoutPresets.load_data(p_name)
	if data.is_empty():
		return false
	cards.load_layout_data(data)
	if decor:
		decor.load_data(data.get("decor", []))
	if is_open():
		cards.set_zones_visible(true)
	preset_name = p_name
	_set_dirty(false)
	_select(null)
	preset_changed.emit(preset_name)
	return true


# --- 3D interaction ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_distance = maxf(_distance * 0.9, 0.45)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_distance = minf(_distance * 1.1, 2.6)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var node := _pick(mb.position)
				if node is DecorPiece:
					_select_decor(node)
					_dragging = true
					var hit: Variant = _decor_drag_hit(mb.position, node)
					_drag_offset = node.global_position - hit if hit != null else Vector3.ZERO
				else:
					_select(node as FlashCard)
					if node:
						_dragging = true
						var hit: Variant = _plane_hit(mb.position, node.global_position.z)
						_drag_offset = node.global_position - hit if hit != null else Vector3.ZERO
			elif _dragging:
				_dragging = false
				_rebuild_card_panel()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_orbit_yaw -= mm.relative.x * 0.005
			_orbit_pitch = clampf(_orbit_pitch + mm.relative.y * 0.005, -0.3, 1.2)
			_update_camera()
		elif _dragging and selected_decor:
			_drag_decor(mm)
		elif _dragging and selected:
			var pos := selected.position
			if mm.shift_pressed:
				pos.z -= mm.relative.y * 0.0015
			else:
				var hit: Variant = _plane_hit(mm.position, selected.global_position.z)
				if hit != null:
					var local := cards.to_local(hit + _drag_offset)
					pos = Vector3(local.x, local.y, pos.z)
			_move_selected(pos)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_toggle"):
		get_viewport().set_input_as_handled()
		close()


func _update_camera() -> void:
	var offset := Basis.from_euler(Vector3(-_orbit_pitch, _orbit_yaw, 0.0)) * Vector3(0, 0, _distance)
	camera.look_at_from_position(focus + offset, focus)
	# Centre the tank in the part of the screen the panel doesn't cover.
	var view := camera.get_viewport().get_visible_rect().size if camera.is_inside_tree() else Vector2(1600, 900)
	var half_height := _distance * tan(deg_to_rad(camera.fov) * 0.5)
	var metres_per_pixel := 2.0 * half_height / view.y
	camera.h_offset = PANEL_WIDTH * 0.5 * metres_per_pixel


## The card or decor piece under the mouse, if any.
func _pick(screen: Vector2) -> Node3D:
	var from := camera.project_ray_origin(screen)
	var to := from + camera.project_ray_normal(screen) * 10.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 2)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var node: Node = hit.collider
	while node and not (node is FlashCard or node is DecorPiece):
		node = node.get_parent()
	return node as Node3D


## Where a drag of `piece` meets its movement plane: horizontal for pieces on
## the gravel, the surface or the rims; parallel to the glass for floating ones.
func _decor_drag_hit(screen: Vector2, piece: DecorPiece) -> Variant:
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if piece.anchor() == "float":
		return Plane(Vector3(0, 0, 1), piece.global_position.z).intersects_ray(origin, dir)
	return Plane(Vector3.UP, piece.global_position.y).intersects_ray(origin, dir)


func _drag_decor(mm: InputEventMouseMotion) -> void:
	var piece := selected_decor
	var pos := piece.position
	if mm.shift_pressed and piece.anchor() == "float":
		pos.z -= mm.relative.y * 0.0015
	else:
		var hit: Variant = _decor_drag_hit(mm.position, piece)
		if hit == null:
			return
		var local := decor.to_local(hit + _drag_offset)
		pos = Vector3(local.x, local.y if piece.anchor() == "float" else pos.y, local.z)
	decor.move_piece(piece, pos)
	_set_dirty(true)


## Where the mouse ray meets the plane z = `z` (global), parallel to the glass.
func _plane_hit(screen: Vector2, z: float) -> Variant:
	var plane := Plane(Vector3(0, 0, 1), z)
	return plane.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))


func _move_selected(pos: Vector3) -> void:
	cards.move_card(selected, cards.clamp_position(pos, water_local))
	_set_dirty(true)


func _select(card: FlashCard) -> void:
	_clear_selection()
	selected = card
	if selected:
		selected.set_selected(true)
	_rebuild_card_panel()


func _select_decor(piece: DecorPiece) -> void:
	_clear_selection()
	selected_decor = piece
	if piece:
		piece.set_selected(true)
	_rebuild_card_panel()


func _clear_selection() -> void:
	if selected and is_instance_valid(selected):
		selected.set_selected(false)
	if selected_decor and is_instance_valid(selected_decor):
		selected_decor.set_selected(false)
	selected = null
	selected_decor = null
	_confirm = ""


# --- panel ---

func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	_layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.x = PANEL_WIDTH - 40
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	_title = _label(box, "Tank editor", 26, Color(1.0, 0.62, 0.25))

	_label(box, "Preset", 15, Color(0.75, 0.8, 0.9))
	var presets := HBoxContainer.new()
	box.add_child(presets)
	_preset_list = OptionButton.new()
	_preset_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	presets.add_child(_preset_list)
	_button(presets, "Load", _on_load)
	_button(presets, "Save", _on_save)
	_button(presets, "Delete", _on_delete)

	var save_as := HBoxContainer.new()
	box.add_child(save_as)
	_save_as_name = LineEdit.new()
	_save_as_name.placeholder_text = "New preset name"
	_save_as_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_as_name.text_submitted.connect(func(_t: String) -> void: _on_save_as())
	save_as.add_child(_save_as_name)
	_button(save_as, "Save as", _on_save_as)

	_status = _label(box, "", 15, Color(1.0, 0.8, 0.5))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	box.add_child(HSeparator.new())
	_label(box, "Add", 15, Color(0.75, 0.8, 0.9))
	var add_row := HBoxContainer.new()
	box.add_child(add_row)
	_button(add_row, "+ Card", _on_add_card)
	_decor_choice = OptionButton.new()
	for id in DecorCatalog.ids():
		_decor_choice.add_item(DecorCatalog.item(id).name)
		_decor_choice.set_item_metadata(_decor_choice.item_count - 1, id)
	_decor_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_decor_choice)
	_button(add_row, "+ Decor", _on_add_decor)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	_button(actions, "Duplicate", _on_duplicate)
	_button(actions, "Delete", _on_delete_selected)
	var hint := _label(box, "Click a card or decor to select it and drag to move it. Shift+drag: depth. Right-drag: orbit. Wheel: zoom.", 14, Color(0.65, 0.7, 0.8))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	box.add_child(HSeparator.new())
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 8)
	box.add_child(_card_box)

	box.add_child(HSeparator.new())
	var done := _button(box, "Done", close)
	done.custom_minimum_size.y = 40


func _rebuild_card_panel() -> void:
	if _card_box == null:
		return
	for child in _card_box.get_children():
		_card_box.remove_child(child)
		child.queue_free()
	if selected_decor and is_instance_valid(selected_decor):
		_rebuild_decor_panel()
		return
	if selected == null or not is_instance_valid(selected):
		_label(_card_box, "Nothing selected.", 16, Color(0.7, 0.75, 0.85))
		return
	var b := selected.binding
	_label(_card_box, b.display_name(), 22, Color.WHITE)

	var kind_row := HBoxContainer.new()
	_card_box.add_child(kind_row)
	_label(kind_row, "Type", 16, Color(0.75, 0.8, 0.9)).custom_minimum_size.x = 70
	var kind := OptionButton.new()
	kind.add_item("Hold", CardBinding.Kind.HOLD)
	kind.add_item("Toggle", CardBinding.Kind.TOGGLE)
	kind.add_item("Sequence", CardBinding.Kind.SEQUENCE)
	kind.select(kind.get_item_index(b.kind))
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kind.item_selected.connect(func(idx: int) -> void: _on_kind_changed(kind.get_item_id(idx)))
	kind_row.add_child(kind)

	var name_row := HBoxContainer.new()
	_card_box.add_child(name_row)
	_label(name_row, "Name", 16, Color(0.75, 0.8, 0.9)).custom_minimum_size.x = 70
	var name_edit := LineEdit.new()
	name_edit.text = b.label
	name_edit.placeholder_text = "(automatic)"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(_on_label_changed)
	name_edit.focus_exited.connect(func() -> void: _on_label_changed(name_edit.text))
	name_row.add_child(name_edit)

	if b.kind != CardBinding.Kind.SEQUENCE:
		var hint := "Held while the fish stays." if b.kind == CardBinding.Kind.HOLD \
			else "Switched on when the fish arrives, off when it arrives again."
		var help := _label(_card_box, hint + " Pick one or more inputs:", 15, Color(0.75, 0.8, 0.9))
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var grid := GridContainer.new()
		grid.columns = 6
		_card_box.add_child(grid)
		for id in CardSystem.INPUTS:
			var toggle := Button.new()
			toggle.toggle_mode = true
			toggle.text = CardSystem.short_name(id)
			toggle.tooltip_text = id
			toggle.custom_minimum_size = Vector2(60, 34)
			toggle.button_pressed = id in b.inputs
			toggle.toggled.connect(_on_hold_input_toggled.bind(id))
			grid.add_child(toggle)
	else:
		var help := _label(_card_box, "Plays once each time the fish arrives. Each step holds an input from its start for its length.", 15, Color(0.75, 0.8, 0.9))
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var header := HBoxContainer.new()
		_card_box.add_child(header)
		for title in ["Input", "Start (ms)", "Length (ms)"]:
			var h := _label(header, title, 13, Color(0.6, 0.65, 0.75))
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(header, "", 13, Color.WHITE).custom_minimum_size.x = 28
		for i in b.steps.size():
			_card_box.add_child(_step_row(i, b.steps[i]))
		_button(_card_box, "+ Step", _on_add_step)
		_label(_card_box, "Total %.2f s" % (b.duration_ms() / 1000.0), 14, Color(0.65, 0.7, 0.8))

	_card_box.add_child(HSeparator.new())
	_label(_card_box, "Position (cm): across, up, depth", 15, Color(0.75, 0.8, 0.9))
	var pos_row := HBoxContainer.new()
	_card_box.add_child(pos_row)
	var p := selected.position
	for axis in 3:
		var spin := SpinBox.new()
		spin.step = 0.5
		spin.min_value = -100
		spin.max_value = 100
		spin.value = snappedf(p[axis] * 100.0, 0.5)
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(_on_position_spin.bind(axis))
		pos_row.add_child(spin)


func _step_row(i: int, step: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	var input := OptionButton.new()
	var ids := CardSystem.INPUTS.keys()
	for id: String in ids:
		input.add_item(CardSystem.short_name(id))
	input.selected = ids.find(step.input)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.item_selected.connect(func(idx: int) -> void: _on_step_changed(i, "input", ids[idx]))
	row.add_child(input)
	for field in ["at", "hold"]:
		var spin := SpinBox.new()
		spin.step = STEP_MS
		# Minimums on the step grid, so values stay round.
		spin.min_value = 0 if field == "at" else ceili(float(CardBinding.MIN_HOLD_MS) / STEP_MS) * STEP_MS
		spin.max_value = CardBinding.MAX_SEQUENCE_MS
		spin.value = step[field]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(func(v: float) -> void: _on_step_changed(i, field, int(v)))
		row.add_child(spin)
	var remove := Button.new()
	remove.text = "✕"
	remove.tooltip_text = "Remove step"
	remove.pressed.connect(_on_remove_step.bind(i))
	row.add_child(remove)
	return row


# --- card edits ---

func _apply(binding: CardBinding) -> void:
	var problem := binding.validate()
	if problem != "":
		_set_status("Not applied: " + problem)
		_rebuild_card_panel()
		return
	var fresh := cards.rebind_card(selected, binding)
	selected = null
	_set_dirty(true)
	_set_status("")
	_select(fresh)


func _on_kind_changed(kind: int) -> void:
	var b := selected.binding
	if kind == b.kind:
		return
	if kind == CardBinding.Kind.SEQUENCE:
		# Turn the held inputs into taps, one after another.
		var steps := []
		var at := 0
		for id in b.all_inputs():
			steps.append({"input": id, "at": at, "hold": 80})
			at += 120
		_apply(CardBinding.sequence(steps, b.label))
	else:
		var held := CardBinding.hold(b.all_inputs())
		held.kind = kind
		held.label = b.label
		_apply(held)


func _on_label_changed(text: String) -> void:
	if selected == null or text.strip_edges() == selected.binding.label:
		return
	var b := selected.binding.duplicate_binding()
	b.label = text.strip_edges()
	_apply(b)


func _on_hold_input_toggled(on: bool, id: String) -> void:
	var b := selected.binding.duplicate_binding()
	if on and id not in b.inputs:
		b.inputs.append(id)
	elif not on:
		var i := b.inputs.find(id)
		if i >= 0:
			b.inputs.remove_at(i)
	_apply(b)


func _on_step_changed(i: int, field: String, value: Variant) -> void:
	var b := selected.binding.duplicate_binding()
	b.steps[i][field] = value
	b.sort_steps()
	_apply(b)


func _on_add_step() -> void:
	var b := selected.binding.duplicate_binding()
	var at := b.duration_ms() + 40
	b.steps.append({"input": "A", "at": at, "hold": 80})
	_apply(b)


func _on_remove_step(i: int) -> void:
	var b := selected.binding.duplicate_binding()
	if b.steps.size() <= 1:
		_set_status("A sequence needs at least one step")
		return
	b.steps.remove_at(i)
	_apply(b)


func _on_position_spin(value: float, axis: int) -> void:
	if selected == null or _dragging:
		return
	var p := selected.position
	p[axis] = value / 100.0
	_move_selected(p)


func _on_add_card() -> void:
	var pos := cards.clamp_position(Vector3(0.0, 0.3, -0.1), water_local)
	var card := cards.add_card(CardBinding.hold(["A"]), pos)
	card.show_zone(cards.zone_for(pos), true)
	_set_dirty(true)
	_select(card)


func _on_duplicate() -> void:
	if selected_decor:
		var d := selected_decor
		var copy := decor.add_piece(d.type, d.position + Vector3(0.08, 0.0, 0.0), d.yaw, d.size, d.variant)
		_set_dirty(true)
		_select_decor(copy)
		return
	if selected == null:
		_set_status("Select something to duplicate")
		return
	var pos := cards.clamp_position(selected.position + Vector3(0.12, 0.0, 0.0), water_local)
	var card := cards.add_card(selected.binding.duplicate_binding(), pos)
	card.show_zone(cards.zone_for(pos), true)
	_set_dirty(true)
	_select(card)


func _on_delete_selected() -> void:
	if selected_decor:
		var piece := selected_decor
		_select(null)
		decor.remove_piece(piece)
		_set_dirty(true)
		return
	_on_delete_card()


func _on_delete_card() -> void:
	if selected == null:
		_set_status("Select something to delete")
		return
	var card := selected
	_select(null)
	cards.remove_card(card)
	_set_dirty(true)


# --- decor ---

func _on_add_decor() -> void:
	var id: String = _decor_choice.get_item_metadata(_decor_choice.selected)
	# Near the middle, a little forward, at a height suiting its anchor.
	var piece := decor.add_piece(id, Vector3(0.0, 0.3, 0.1), 0.0, "M", 0)
	_set_dirty(true)
	_select_decor(piece)


func _rebuild_decor_panel() -> void:
	var d := selected_decor
	var item := d.info()
	_label(_card_box, item.name, 22, Color.WHITE)
	var kind := "Solid: the fish bumps into it" if d.is_solid() else "Soft: the fish swims through"
	_label(_card_box, kind, 14, Color(0.65, 0.7, 0.8))

	var colour_row := HBoxContainer.new()
	_card_box.add_child(colour_row)
	_label(colour_row, "Colour", 16, Color(0.75, 0.8, 0.9)).custom_minimum_size.x = 70
	var colours := OptionButton.new()
	for v: Dictionary in item.variants:
		colours.add_item(v.name)
	colours.selected = d.variant
	colours.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	colours.item_selected.connect(func(i: int) -> void:
		d.set_look(i, d.size, d.yaw)
		_set_dirty(true)
		_select_decor(d))
	colour_row.add_child(colours)

	var size_row := HBoxContainer.new()
	_card_box.add_child(size_row)
	_label(size_row, "Size", 16, Color(0.75, 0.8, 0.9)).custom_minimum_size.x = 70
	for s: String in DecorPiece.SIZES:
		var b := Button.new()
		b.text = s
		b.toggle_mode = true
		b.button_pressed = s == d.size
		b.custom_minimum_size = Vector2(48, 32)
		b.pressed.connect(func() -> void:
			d.set_look(d.variant, s, d.yaw)
			decor.move_piece(d, d.position)
			_set_dirty(true)
			_select_decor(d))
		size_row.add_child(b)

	if d.anchor() != "rim":
		var turn_row := HBoxContainer.new()
		_card_box.add_child(turn_row)
		_label(turn_row, "Turn", 16, Color(0.75, 0.8, 0.9)).custom_minimum_size.x = 70
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 360
		slider.step = 5
		slider.value = d.yaw
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.y = 28
		var readout := _label(turn_row, "%d°" % int(d.yaw), 15, Color(0.85, 0.9, 1.0))
		readout.custom_minimum_size.x = 44
		slider.value_changed.connect(func(v: float) -> void:
			d.set_yaw(v)
			readout.text = "%d°" % int(v)
			_set_dirty(true))
		turn_row.add_child(slider)
		turn_row.move_child(slider, 1)
	else:
		_label(_card_box, "Hangs on the back or side rim; drag to move it along.", 14, Color(0.65, 0.7, 0.8))

	var where: String = {"gravel": "Sits on the gravel.", "surface": "Floats on the water.",
		"float": "Floats in the water. Shift+drag: depth.", "rim": ""}[d.anchor()]
	if where != "":
		_label(_card_box, where, 14, Color(0.65, 0.7, 0.8))


## Cards and decor together, as a preset.
func layout_data(p_name: String) -> Dictionary:
	var data := cards.layout_data(p_name)
	if decor:
		data.decor = decor.to_data()
	return data


# --- presets ---

func _refresh_presets() -> void:
	_preset_list.clear()
	var i := 0
	for p in LayoutPresets.list():
		_preset_list.add_item(p.name + ("  (built in)" if p.builtin else ""))
		_preset_list.set_item_metadata(i, p.name)
		if p.name == preset_name:
			_preset_list.selected = i
		i += 1
	_update_title()


func _chosen_preset() -> String:
	if _preset_list.selected < 0:
		return ""
	return _preset_list.get_item_metadata(_preset_list.selected)


## For actions that throw away work: the first click asks, the second does it.
func _confirmed(action: String, question: String) -> bool:
	if not dirty or _confirm == action:
		_confirm = ""
		return true
	_confirm = action
	_set_status(question)
	return false


func _on_load() -> void:
	var p := _chosen_preset()
	if p == "" or not _confirmed("load", "Unsaved changes will be lost. Click Load again to load '%s'." % p):
		return
	if load_preset(p):
		_set_status("Loaded '%s'" % p)


func _on_save() -> void:
	if LayoutPresets.is_builtin(preset_name):
		_set_status("'%s' is built in. Type a name and use Save as." % preset_name)
		_save_as_name.grab_focus()
		return
	_save(preset_name)


func _on_save_as() -> void:
	_save(_save_as_name.text)


func _save(p_name: String) -> void:
	p_name = p_name.strip_edges()
	var error := LayoutPresets.save(p_name, layout_data(p_name))
	if error != "":
		_set_status(error)
		return
	preset_name = p_name
	_save_as_name.text = ""
	_set_dirty(false)
	_refresh_presets()
	_set_status("Saved '%s'" % p_name)
	preset_changed.emit(preset_name)


func _on_delete() -> void:
	var p := _chosen_preset()
	if LayoutPresets.is_builtin(p):
		_set_status("Built-in presets can't be deleted")
		return
	if _confirm != "delete":
		_confirm = "delete"
		_set_status("Click Delete again to delete '%s'." % p)
		return
	_confirm = ""
	var error := LayoutPresets.delete(p)
	if error != "":
		_set_status(error)
		return
	if p == preset_name:
		load_preset(LayoutPresets.DEFAULT)
	_refresh_presets()
	_set_status("Deleted '%s'" % p)


func _set_dirty(value: bool) -> void:
	dirty = value
	_update_title()


func _update_title() -> void:
	if _title:
		_title.text = "Tank editor · %s%s" % [preset_name, "  •  unsaved" if dirty else ""]


func _set_status(text: String) -> void:
	if _status:
		_status.text = text


func _label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	parent.add_child(b)
	return b
