class_name ControlsPage
extends HBoxContainer
## The monitor's Controls page: a column per player, up to four, each worked by
## its own player at once: their gamepad moves a cursor in their column only
## (player 1's keyboard and mouse work theirs). A column holds the player's
## fish, picked on a turning carousel, and their own controls: steering,
## invert look, look speed; player 1's also says what they play with (the
## keyboard alone, or with a gamepad too), the
## others' can leave. Empty columns invite another gamepad to join (Start).
## B, Esc or Start goes back, from any player.
##
## Godot's GUI has one focus per viewport, so the columns keep their own
## cursors and take their players' input here, before the GUI sees it.

const PLAYER_COLORS := [Color(1.0, 0.6, 0.25), Color(0.35, 0.8, 0.85), Color(0.7, 0.55, 1.0), Color(0.6, 0.85, 0.35)]
const STICK_EDGE := 0.6

var players: Players
## Called to leave the page.
var on_back: Callable

var _columns: Array[ControlsColumn] = []
var _cursors := {}  ## player number -> row index
var _stick := {}    ## device -> [x, y] last stick values, for edges


func _init(p_players: Players, p_on_back: Callable) -> void:
	players = p_players
	on_back = p_on_back
	name = "ControlsPage"
	add_theme_constant_override("separation", 14)
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	for i in Players.MAX:
		var col := ControlsColumn.new(self, i + 1)
		_columns.append(col)
		add_child(col)
	refresh()
	players.changed.connect(refresh)


func _exit_tree() -> void:
	if players.changed.is_connected(refresh):
		players.changed.disconnect(refresh)


## Brings every column up to date with the players (joined, left, changed).
func refresh() -> void:
	for col in _columns:
		var p: Players.Player = players.list[col.number - 1] if col.number <= players.list.size() else null
		if p and p.choosing:
			p.choosing = false  # they pick here instead of in their view
		col.show_player(p)


func cursor(number: int) -> int:
	return _cursors.get(number, 0)


func set_cursor(number: int, value: int) -> void:
	_cursors[number] = value
	_columns[number - 1].update_cursor()


# --- input ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var p: Players.Player = null
	var move := Vector2i.ZERO
	var activate := false
	var back := false
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		p = players.owner_of(event.device)
		if p == null:
			return  # Players handles a new pad's Start (joining)
		if event is InputEventJoypadButton:
			if not event.pressed:
				_consume()
				return
			match event.button_index:
				JOY_BUTTON_DPAD_UP:
					move.y = -1
				JOY_BUTTON_DPAD_DOWN:
					move.y = 1
				JOY_BUTTON_DPAD_LEFT:
					move.x = -1
				JOY_BUTTON_DPAD_RIGHT:
					move.x = 1
				JOY_BUTTON_A:
					activate = true
				JOY_BUTTON_B, JOY_BUTTON_START:
					back = true
		else:
			move = _stick_edge(event)
	elif event is InputEventKey:
		if not event.pressed:
			return
		p = players.list[0]
		match event.physical_keycode:
			KEY_UP, KEY_W:
				move.y = -1
			KEY_DOWN, KEY_S:
				move.y = 1
			KEY_LEFT, KEY_A:
				move.x = -1
			KEY_RIGHT, KEY_D:
				move.x = 1
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				activate = true
			KEY_ESCAPE, KEY_BACKSPACE:
				back = true
			_:
				return
	else:
		return  # the mouse goes to player 1's column's own buttons
	_consume()
	if back:
		on_back.call()
		return
	if p == null:
		return
	var col := _columns[p.number - 1]
	if move.y != 0:
		set_cursor(p.number, clampi(cursor(p.number) + move.y, 0, col.row_count() - 1))
	elif move.x != 0:
		col.step(cursor(p.number), move.x)
	elif activate:
		col.activate(cursor(p.number))


func _consume() -> void:
	get_viewport().set_input_as_handled()


## The left stick as a d-pad: one step each time it crosses STICK_EDGE.
func _stick_edge(event: InputEventJoypadMotion) -> Vector2i:
	if event.axis != JOY_AXIS_LEFT_X and event.axis != JOY_AXIS_LEFT_Y:
		return Vector2i.ZERO
	var was: Array = _stick.get(event.device, [0.0, 0.0])
	var i := 0 if event.axis == JOY_AXIS_LEFT_X else 1
	var before: float = was[i]
	was[i] = event.axis_value
	_stick[event.device] = was
	if absf(event.axis_value) > STICK_EDGE and absf(before) <= STICK_EDGE:
		var d := int(signf(event.axis_value))
		return Vector2i(d, 0) if i == 0 else Vector2i(0, d)
	return Vector2i.ZERO


# --- a column ----------------------------------------------------------------------

class ControlsColumn:
	extends PanelContainer

	var page: ControlsPage
	var number := 1
	var player: Players.Player
	var _box: VBoxContainer
	var _rows: Array[Control] = []
	var _values: Array[Label] = []
	var _preview: FishPreview
	var _fish_name: Label

	func _init(p_page: ControlsPage, p_number: int) -> void:
		page = p_page
		number = p_number
		# Equal columns, whatever they hold.
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		custom_minimum_size.x = 244
		_box = VBoxContainer.new()
		_box.add_theme_constant_override("separation", 2)
		add_child(_box)

	func _color() -> Color:
		return ControlsPage.PLAYER_COLORS[number - 1]

	func show_player(p: Players.Player) -> void:
		if p == player and p != null and not _rows.is_empty():
			_update_values()
			return
		player = p
		for c in _box.get_children():
			_box.remove_child(c)
			c.queue_free()
		_rows.clear()
		_values.clear()
		_preview = null
		var style := UiStyle.box(UiStyle.RAISED if p else Color(UiStyle.RAISED, 0.35), 14, 10)
		style.border_width_top = 4
		style.border_color = _color() if p else Color(_color(), 0.35)
		add_theme_stylebox_override("panel", style)
		if p == null:
			_empty()
			return
		var title := _text("Player %d" % number, 22, _color(), 800)
		_box.add_child(title)
		_box.add_child(_text(_device_text(), 15, UiStyle.MUTED, 600))
		# The fish carousel.
		var fish_row := VBoxContainer.new()
		fish_row.add_theme_constant_override("separation", 0)
		_preview = FishPreview.new(p.variety)
		_preview.custom_minimum_size = Vector2(0, 92)
		fish_row.add_child(_preview)
		var name_row := HBoxContainer.new()
		name_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_arrow(name_row, "◀", 0, -1)
		_fish_name = _text("", 19, UiStyle.TEXT, 800)
		_fish_name.custom_minimum_size.x = 120
		_fish_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_row.add_child(_fish_name)
		_arrow(name_row, "▶", 0, 1)
		fish_row.add_child(name_row)
		_add_row(fish_row, null)
		_value_row("Steering", ["Turn", "Point"])
		_value_row("Invert look", ["Off", "On"])
		_value_row("Look speed", Players.LOOK_SPEEDS.map(func(v: float) -> String: return "%s×" % str(v)))
		if number == 1:
			# The keyboard always works for player 1; Gamepad adds the first pad they use.
			_value_row("Input", ["Keyboard", "Gamepad"])
			_button_row("Back")
		else:
			_button_row("Leave")
		_update_values()
		# Only player 1's column answers the mouse.
		if number != 1:
			_ignore_mouse(self)
		update_cursor()

	func _empty() -> void:
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_box.add_child(spacer)
		var join := _text("Press %s\non a gamepad\nto join" % Glyphs.label("START"), 22, UiStyle.MUTED, 800)
		join.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(join)
		var spacer2 := Control.new()
		spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_box.add_child(spacer2)

	func _device_text() -> String:
		if number == 1:
			return "Keyboard & gamepad" if player.input.pad >= 0 else "Keyboard"
		return "Gamepad"

	func row_count() -> int:
		return _rows.size()

	func _add_row(control: Control, value: Label) -> void:
		var panel := PanelContainer.new()
		panel.add_child(control)
		_box.add_child(panel)
		_rows.append(panel)
		_values.append(value)

	## A setting's ◀ value ▶ row (Stepper, as on the Settings page), lit by
	## this column's cursor rather than by focus.
	func _value_row(label: String, options: Array) -> void:
		var stepper := Stepper.new(label, options, 0, 15, 84)
		stepper.focus_mode = Control.FOCUS_NONE
		stepper.accent = _color()
		var i := _rows.size()
		stepper.item_selected.connect(func(index: int) -> void:
			page.set_cursor(number, i)
			_apply(i, index))
		_box.add_child(stepper)
		_rows.append(stepper)
		_values.append(null)

	func _button_row(label: String) -> void:
		var b := Button.new()
		b.text = label
		b.add_theme_font_size_override("font_size", 16)
		b.focus_mode = Control.FOCUS_NONE
		var i := _rows.size()
		b.pressed.connect(func() -> void:
			page.set_cursor(number, i)
			activate(i))
		_add_row(b, null)

	## The fish carousel's arrows.
	func _arrow(row: HBoxContainer, glyph: String, row_index: int, dir: int) -> void:
		var b := Button.new()
		b.text = glyph
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void:
			page.set_cursor(number, row_index)
			step(row_index, dir))
		row.add_child(b)

	## Left / right on a row: the fish carousel, or a setting's stepper.
	func step(row: int, dir: int) -> void:
		if row == 0:
			page.players.set_variety(player, player.variety + dir)
		elif _rows[row] is Stepper:
			(_rows[row] as Stepper).step(dir)

	## A stepper row's new choice, applied to the player.
	func _apply(row: int, index: int) -> void:
		var pl := page.players
		match row:
			1:
				pl.set_steering(player, "camera" if index == 1 else "fish")
			2:
				pl.set_invert_y(player, index == 1)
			3:
				pl.set_look_speed(player, Players.LOOK_SPEEDS[index])
			4:
				pl.set_p1_uses_pad(index == 1)

	## A (or Enter, or a click) on a row: buttons act, values step on.
	func activate(row: int) -> void:
		if row == row_count() - 1:  # the last row: Back for player 1, Leave for the others
			if number == 1:
				page.on_back.call()
			else:
				page.players.leave(player)
			return
		step(row, 1)

	func _update_values() -> void:
		if player == null:
			return
		_fish_name.text = FishModel.VARIETIES[player.variety]
		if _preview:
			_preview.set_variety(player.variety)
		(_rows[1] as Stepper).select(1 if player.steering == "camera" else 0)
		(_rows[2] as Stepper).select(1 if player.invert_y else 0)
		(_rows[3] as Stepper).select(maxi(Players.LOOK_SPEEDS.find(player.look_speed), 0))
		if number == 1:
			(_rows[4] as Stepper).select(1 if page.players.p1_uses_pad else 0)
		(_box.get_child(1) as Label).text = _device_text()

	func update_cursor() -> void:
		var at := page.cursor(number)
		for i in _rows.size():
			if _rows[i] is Stepper:
				(_rows[i] as Stepper).lit = i == at
				continue
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(10)
			sb.content_margin_left = 8
			sb.content_margin_right = 8
			sb.content_margin_top = 1
			sb.content_margin_bottom = 1
			if i == at:
				sb.bg_color = Color(_color(), 0.22)
				sb.border_color = _color()
				sb.set_border_width_all(2)
			else:
				sb.bg_color = Color(0, 0, 0, 0)
			_rows[i].add_theme_stylebox_override("panel", sb)

	func _text(t: String, size: int, color: Color, weight: int) -> Label:
		var l := Label.new()
		l.text = t
		l.add_theme_font_override("font", UiStyle.font(weight))
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", color)
		return l

	func _ignore_mouse(node: Node) -> void:
		if node is Control:
			(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		for c in node.get_children():
			_ignore_mouse(c)


# --- the carousel's fish ---------------------------------------------------------------

## A fish turning slowly on its own little stage, swimming gently, in a
## colouring.
class FishPreview:
	extends SubViewportContainer

	var _fish: Fish
	var _model: FishModel
	var _pivot: Node3D
	var _variety := 0

	func _init(variety: int) -> void:
		_variety = variety
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.msaa_3d = Viewport.MSAA_4X
		add_child(vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.8, 0.85, 0.95)
		env.ambient_light_energy = 0.7
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, 35, 0)
		sun.light_energy = 1.5
		vp.add_child(sun)
		# A fish to read the swimming from; it isn't in the tree, so it stays put.
		_fish = Fish.new()
		_fish.effort = 0.12
		_pivot = Node3D.new()
		vp.add_child(_pivot)
		_model = FishModel.new(_fish)
		_pivot.add_child(_model)
		_model.variety = _variety
		var cam := Camera3D.new()
		cam.fov = 26.0
		vp.add_child(cam)
		cam.look_at_from_position(Vector3(0.0, 0.03, 0.19), Vector3(0.0, 0.004, 0.0))

	func _exit_tree() -> void:
		if is_instance_valid(_fish):
			_fish.free()

	func set_variety(v: int) -> void:
		_variety = v
		if _model:
			_model.variety = v

	func _process(delta: float) -> void:
		if _pivot == null:
			return
		_pivot.rotate_y(delta * 0.5)
		_fish.tail_phase = fmod(_fish.tail_phase + TAU * 1.4 * delta, TAU * 64.0)
		_fish.fin_phase += TAU * 2.0 * delta
