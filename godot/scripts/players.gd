class_name Players
extends Node
## The local players: up to four fish in the one tank, each piloted by its own
## player, all pressing the same cards (one virtual controller on the host).
##
## Player 1 plays with the keyboard and mouse, plus (unless set to keyboard
## only on the monitor) the first gamepad they use. Pressing Start on any
## other gamepad drops a new fish into the tank: its player picks the fish's
## colouring in their own view (left / right, then A), and leaves again by
## holding Back. Player 1 picks theirs on the monitor.
##
## While swimming with two or more players the screen splits: two side by
## side, three or four in quarters (with three, the fourth quarter shows the
## room camera's view of the tank). Each view is a SubViewport onto the main
## world, with that player's follow camera in it. In the menu and the editor
## everyone shares the full screen, as before.
##
## Sound is heard from between the fish (`ears`, which main.gd makes current).

signal changed

const MAX := 4
## How long players 2 and up hold Back to leave.
const LEAVE_HOLD := 1.5
## Where each player's fish first appears (tank space), and which way it faces.
const SPAWNS := [[Vector3(0.3, 0.3, 0.1), PI / 2], [Vector3(-0.3, 0.3, 0.1), -PI / 2],
	[Vector3(0.3, 0.42, -0.1), PI / 2], [Vector3(-0.3, 0.42, -0.1), -PI / 2]]
const FAR := Vector3(0.0, -100.0, 0.0)


class Player:
	extends RefCounted
	var number := 1  ## 1..4, as shown
	var input: PlayerInput
	var fish: Fish
	var camera: FishCamera
	var variety := 0
	## Picking a colouring after joining: the fish waits.
	var choosing := false
	var holder: SubViewportContainer
	var chooser: Label
	var back_time := 0.0


var list: Array[Player] = []
## Builds a fish (main.gd's _make_fish).
var make_fish: Callable
var tank: Node3D
var water := AABB()
var screen: Node3D
var screen_size := Vector2.ONE
var room_camera: Camera3D
## Heard from between the fish.
var ears: AudioListener3D
## Whether player 1 also takes the first gamepad they use.
var p1_uses_pad := true
var swimming := false
var editing := false

var _layer: CanvasLayer
var _grid: GridContainer
var _stick_was := {}


func _ready() -> void:
	p1_uses_pad = Settings.get_value("players", "p1_pad", true)
	Quality.changed.connect(func(_l: int) -> void: _match_quality())


## Player 1: the keyboard and mouse (and their first pad). Called once by main.gd.
func add_first() -> Player:
	var p := _add(PlayerInput.new(true, -1), int(Settings.get_value("players", "p1_fish", 0)))
	return p


## Drops a new fish in for gamepad `device`. Returns null if the tank is full
## or the pad already has a fish.
func join(device: int) -> Player:
	if list.size() >= MAX or owner_of(device) != null:
		return null
	var p := _add(PlayerInput.new(false, device), _unused_variety())
	p.choosing = true
	_apply_state()
	_layout()
	changed.emit()
	return p


func leave(p: Player) -> void:
	if p.number == 1 or p not in list:
		return
	list.erase(p)
	if p.holder:
		p.holder.queue_free()
	p.camera.queue_free()
	p.fish.queue_free()
	for i in list.size():
		list[i].number = i + 1
	_layout()
	changed.emit()


## The player whose pad is `device`, if any.
func owner_of(device: int) -> Player:
	for p in list:
		if p.input.pad == device:
			return p
	return null


func set_variety(p: Player, value: int, remember := true) -> void:
	p.variety = wrapi(value, 0, FishModel.VARIETIES.size())
	_model(p.fish).variety = p.variety
	if p.number == 1 and remember:
		Settings.set_value("players", "p1_fish", p.variety)
	if p.chooser:
		_update_chooser(p)
	changed.emit()


func set_p1_uses_pad(value: bool) -> void:
	p1_uses_pad = value
	Settings.set_value("players", "p1_pad", value)
	if not value and not list.is_empty():
		list[0].input.pad = -1
	changed.emit()


## The menu and the editor: everyone on the full screen, fish stopped.
func set_mode(p_swimming: bool, p_editing: bool) -> void:
	swimming = p_swimming
	editing = p_editing
	_apply_state()
	_layout()


func _apply_state() -> void:
	for p in list:
		var steer := swimming and not p.choosing
		p.fish.player_control = steer
		if not steer:
			p.fish.drive(Vector3.ZERO, 0.0)
		p.fish.set_physics_process(not editing)
		# Player 1's camera frames the monitor in the menu.
		p.camera.menu_view = not swimming if p.number == 1 else false


func _add(input: PlayerInput, variety: int) -> Player:
	var p := Player.new()
	p.number = list.size() + 1
	p.input = input
	p.variety = variety
	var fish: Fish = make_fish.call()
	fish.name = "Fish" if p.number == 1 else "Fish%d" % p.number
	fish.bounds = water
	fish.input = input
	tank.add_child(fish)
	var spawn: Array = SPAWNS[list.size()]
	fish.position = spawn[0]
	fish.yaw = spawn[1]
	fish.global_basis = Basis.from_euler(Vector3(0, fish.yaw, 0))
	var sounds := FishSounds.new()
	sounds.name = "FishSounds"
	fish.add_child(sounds)
	_model(fish).variety = variety
	var cam := FishCamera.new()
	cam.fish = fish
	cam.input = input
	fish.view = cam
	cam.screen = screen
	cam.screen_size = screen_size
	cam.bounds = water
	add_child(cam)
	p.fish = fish
	p.camera = cam
	list.append(p)
	return p


func _model(fish: Fish) -> FishModel:
	for c in fish.get_children():
		if c is FishModel:
			return c
	return null


func _unused_variety() -> int:
	for v in FishModel.VARIETIES.size():
		if list.all(func(p: Player) -> bool: return p.variety != v):
			return v
	return 0


# --- input: joining, choosing, leaving -------------------------------------------

func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	var device: int = event.device
	var p := owner_of(device)
	if p == null:
		var pressed: bool = event is InputEventJoypadButton and event.pressed
		if list.is_empty() or not pressed:
			return
		var first := list[0]
		if p1_uses_pad and first.input.pad < 0:
			first.input.pad = device  # player 1 picks up a pad
			changed.emit()
		elif event.button_index == JOY_BUTTON_START and join(device) != null:
			get_viewport().set_input_as_handled()  # not the menu
		return
	if p.choosing:
		_choose(p, event)
		get_viewport().set_input_as_handled()


## Left / right through the colourings, A to start swimming.
func _choose(p: Player, event: InputEvent) -> void:
	var step := 0
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT:
				step = -1
			JOY_BUTTON_DPAD_RIGHT:
				step = 1
			JOY_BUTTON_A:
				p.choosing = false
				_apply_state()
				_layout()
				return
	elif event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X:
		var was: float = _stick_was.get(p.input.pad, 0.0)
		if absf(event.axis_value) > 0.6 and absf(was) <= 0.6:
			step = int(signf(event.axis_value))
		_stick_was[p.input.pad] = event.axis_value
	if step != 0:
		set_variety(p, p.variety + step)


func _process(delta: float) -> void:
	if list.is_empty():
		return
	# Holding Back to leave.
	for p in list.duplicate():
		if p.number > 1 and p.input.back_held():
			p.back_time += delta
			if p.back_time >= LEAVE_HOLD:
				leave(p)
		else:
			p.back_time = 0.0
	# Heard from between the fish, facing as player 1's fish does.
	if ears:
		var mid := Vector3.ZERO
		for p in list:
			mid += p.fish.global_position
		ears.global_transform = Transform3D(list[0].fish.global_basis, mid / list.size())
	# Where every fish is, for the plants to lean away from.
	var names := ["fish_position", "fish_position_2", "fish_position_3", "fish_position_4"]
	for i in names.size():
		RenderingServer.global_shader_parameter_set(names[i], list[i].fish.global_position if i < list.size() else FAR)


# --- split screen ------------------------------------------------------------------

func is_split() -> bool:
	return _layer != null


func _layout() -> void:
	var split := swimming and list.size() >= 2
	if not split:
		if _layer:
			for p in list:
				p.camera.reparent(self)
				p.holder = null
				p.chooser = null
			_layer.queue_free()
			_layer = null
			_grid = null
			get_viewport().disable_3d = false
		if not list.is_empty() and not editing:
			list[0].camera.make_current()
		return
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.name = "SplitScreen"
		_layer.layer = -1  # under the menus and overlays
		add_child(_layer)
		_grid = GridContainer.new()
		_grid.set_anchors_preset(Control.PRESET_FULL_RECT)
		_grid.add_theme_constant_override("h_separation", 4)
		_grid.add_theme_constant_override("v_separation", 4)
		_layer.add_child(_grid)
		# The full-screen view would only be drawn over.
		get_viewport().disable_3d = true
	for p in list:
		if p.camera.get_parent() != self:
			p.camera.reparent(self)  # out of the views about to go
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_grid.columns = 2
	for p in list:
		p.holder = _view(p.camera)
		_grid.add_child(p.holder)
		p.chooser = null
		if p.choosing:
			_add_chooser(p)
	if list.size() == 3:
		# The fourth quarter: the room camera's view of the tank.
		var cam := Camera3D.new()
		cam.fov = room_camera.fov if room_camera else 32.0
		var holder := _view(cam)
		_grid.add_child(holder)
		if room_camera:
			cam.global_transform = room_camera.global_transform
	_match_quality()


## A SubViewport onto the main world, with `cam` in it, filling its cell.
func _view(cam: Camera3D) -> SubViewportContainer:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vp := SubViewport.new()
	vp.world_3d = get_viewport().world_3d
	vp.audio_listener_enable_3d = false
	holder.add_child(vp)
	if cam.get_parent():
		cam.reparent(vp)
	else:
		vp.add_child(cam)
	cam.make_current()
	return holder


func _add_chooser(p: Player) -> void:
	var label := Label.new()
	label.add_theme_font_override("font", UiStyle.font(800))
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.offset_top = -110
	label.offset_bottom = -40
	label.offset_left = -300
	label.offset_right = 300
	p.holder.get_child(0).add_child(label)
	p.chooser = label
	_update_chooser(p)


func _update_chooser(p: Player) -> void:
	if p.chooser:
		p.chooser.text = "Player %d\n◀  %s  ▶     %s to swim" % [p.number, FishModel.VARIETIES[p.variety], Glyphs.label("A")]


## The split views render at the quality level's anti-aliasing and scale.
func _match_quality() -> void:
	if _grid == null:
		return
	var root := get_viewport()
	for holder in _grid.get_children():
		var vp := holder.get_child(0) as SubViewport
		vp.msaa_3d = root.msaa_3d
		vp.scaling_3d_scale = root.scaling_3d_scale
		vp.positional_shadow_atlas_size = root.positional_shadow_atlas_size
