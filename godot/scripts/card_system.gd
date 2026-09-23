class_name CardSystem
extends Node3D
## Turns the fish's position into controller input on the host.
##
## Each card's trigger zone is the middle of the card's footprint (ZONE_SCALE
## of it) extruded forward to the front glass. Since every card faces the glass, the zones
## match what the room camera sees: the fish "in front of" a card from the
## camera's point of view is pressing it.
##
## A card presses the moment the centre of the fish enters its zone. The rest of
## the body doesn't count, so brushing past with a fin or the tail does nothing.
## It releases once the fish has been clear of it (plus a small hysteresis
## margin) for RELEASE_DELAY, so a fish drifting along a boundary doesn't
## flicker the button. Buttons are held for as long as the fish stays.

signal held_changed(inputs: PackedStringArray)

const CARD_SIZE := Vector2(0.11, 0.08)
const ZONE_SCALE := 0.9
const HYSTERESIS := 0.015
const RELEASE_DELAY := 0.15
const STICK_MAX := 32767
const TRIGGER_MAX := 255

# Button flags, matching Limelight.h (and MoonlightClient.BUTTON_*).
const BUTTON_FLAGS := {
	"A": 0x1000, "B": 0x2000, "X": 0x4000, "Y": 0x8000,
	"DPAD_UP": 0x0001, "DPAD_DOWN": 0x0002, "DPAD_LEFT": 0x0004, "DPAD_RIGHT": 0x0008,
	"START": 0x0010, "BACK": 0x0020, "L3": 0x0040, "R3": 0x0080,
	"LB": 0x0100, "RB": 0x0200,
}

const _STICK_L := Color(0.32, 0.36, 0.45)
const _STICK_R := Color(0.45, 0.34, 0.5)
const _DPAD := Color(0.3, 0.3, 0.3)
const _SHOULDER := Color(0.22, 0.24, 0.3)

## Everything a card can be bound to. `stick` entries push that stick fully in a
## direction (y-up), `trigger` entries pull a trigger fully.
const INPUTS := {
	"A": {"label": "A", "color": Color(0.24, 0.7, 0.3)},
	"B": {"label": "B", "color": Color(0.85, 0.22, 0.2)},
	"X": {"label": "X", "color": Color(0.2, 0.45, 0.9)},
	"Y": {"label": "Y", "color": Color(0.95, 0.75, 0.1)},
	"LB": {"label": "LB", "color": _SHOULDER},
	"RB": {"label": "RB", "color": _SHOULDER},
	"LT": {"label": "LT", "color": _SHOULDER, "trigger": "left"},
	"RT": {"label": "RT", "color": _SHOULDER, "trigger": "right"},
	"START": {"label": "START", "color": _SHOULDER},
	"BACK": {"label": "BACK", "color": _SHOULDER},
	"DPAD_UP": {"arrow": Vector2(0, 1), "caption": "D-PAD", "color": _DPAD},
	"DPAD_DOWN": {"arrow": Vector2(0, -1), "caption": "D-PAD", "color": _DPAD},
	"DPAD_LEFT": {"arrow": Vector2(-1, 0), "caption": "D-PAD", "color": _DPAD},
	"DPAD_RIGHT": {"arrow": Vector2(1, 0), "caption": "D-PAD", "color": _DPAD},
	"L_UP": {"arrow": Vector2(0, 1), "caption": "LEFT STICK", "color": _STICK_L, "stick": "left"},
	"L_DOWN": {"arrow": Vector2(0, -1), "caption": "LEFT STICK", "color": _STICK_L, "stick": "left"},
	"L_LEFT": {"arrow": Vector2(-1, 0), "caption": "LEFT STICK", "color": _STICK_L, "stick": "left"},
	"L_RIGHT": {"arrow": Vector2(1, 0), "caption": "LEFT STICK", "color": _STICK_L, "stick": "left"},
	"L3": {"label": "L3", "caption": "LEFT STICK", "color": _STICK_L},
	"R_UP": {"arrow": Vector2(0, 1), "caption": "RIGHT STICK", "color": _STICK_R, "stick": "right"},
	"R_DOWN": {"arrow": Vector2(0, -1), "caption": "RIGHT STICK", "color": _STICK_R, "stick": "right"},
	"R_LEFT": {"arrow": Vector2(-1, 0), "caption": "RIGHT STICK", "color": _STICK_R, "stick": "right"},
	"R_RIGHT": {"arrow": Vector2(1, 0), "caption": "RIGHT STICK", "color": _STICK_R, "stick": "right"},
	"R3": {"label": "R3", "caption": "RIGHT STICK", "color": _STICK_R},
}

## Receives send_controller_state(); normally the MoonlightClient.
var client: Object
var fish: Node3D
## Z of the inside of the front glass, in this node's space.
var front_z := 0.25
## When false (menus open), every card is released.
var enabled := true:
	set = set_enabled

var cards: Array[FlashCard] = []
var _zones: Array[AABB] = []
var _release_timers: Array[float] = []
var _state := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
var _show_zones := false


func load_layout(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("cards"):
		push_error("CardSystem: can't read layout " + path)
		return false
	for card in cards:
		card.queue_free()
	cards.clear()
	_zones.clear()
	_release_timers.clear()
	for entry: Dictionary in data.cards:
		var id: String = entry.input
		if not INPUTS.has(id):
			push_warning("CardSystem: unknown input '%s' in %s" % [id, path])
			continue
		var p: Array = entry.position
		add_card(id, Vector3(p[0], p[1], p[2]))
	return true


func add_card(input_id: String, pos: Vector3) -> FlashCard:
	var card := FlashCard.new(input_id, CARD_SIZE)
	card.position = pos
	add_child(card)
	cards.append(card)
	_zones.append(zone_for(pos))
	_release_timers.append(0.0)
	return card


## The trigger zone of a card centred at `pos`: the middle of its footprint,
## extruded from the card face to the front glass.
func zone_for(pos: Vector3) -> AABB:
	var half := CARD_SIZE * ZONE_SCALE * 0.5
	var z0 := pos.z + 0.003
	return AABB(Vector3(pos.x - half.x, pos.y - half.y, z0), Vector3(half.x * 2.0, half.y * 2.0, maxf(front_z - z0, 0.001)))


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		for i in cards.size():
			cards[i].active = false
			_release_timers[i] = 0.0
		_publish()


func _physics_process(delta: float) -> void:
	if fish == null or not enabled:
		return
	update(to_local(fish.global_position), delta)


## Advances the press/release logic for the fish's centre at `fish_pos` (this node's space).
func update(fish_pos: Vector3, delta: float) -> void:
	for i in cards.size():
		var card := cards[i]
		var zone := _zones[i].grow(HYSTERESIS) if card.active else _zones[i]
		if zone.has_point(fish_pos):
			card.active = true
			_release_timers[i] = RELEASE_DELAY
		elif card.active:
			_release_timers[i] -= delta
			if _release_timers[i] <= 0.0:
				card.active = false
	_publish()


## Resends the current state, e.g. when a stream (re)starts.
func resend() -> void:
	if client:
		client.send_controller_state(_state[0], _state[1], _state[2], _state[3], _state[4], _state[5], _state[6])


func held() -> PackedStringArray:
	var out := PackedStringArray()
	for card in cards:
		if card.active and card.input_id not in out:
			out.append(card.input_id)
	return out


## [buttons, left_trigger, right_trigger, left_x, left_y, right_x, right_y]
func controller_state() -> PackedInt32Array:
	return _state


func toggle_zones() -> void:
	_show_zones = not _show_zones
	for i in cards.size():
		cards[i].show_zone(_zones[i], _show_zones)


func _publish() -> void:
	var buttons := 0
	var triggers := Vector2i.ZERO
	var left := Vector2.ZERO
	var right := Vector2.ZERO
	for card in cards:
		if not card.active:
			continue
		var id := card.input_id
		var info: Dictionary = INPUTS[id]
		if BUTTON_FLAGS.has(id):
			buttons |= BUTTON_FLAGS[id]
		elif info.has("trigger"):
			if info.trigger == "left":
				triggers.x = TRIGGER_MAX
			else:
				triggers.y = TRIGGER_MAX
		elif info.has("stick"):
			if info.stick == "left":
				left += info.arrow
			else:
				right += info.arrow
	left = left.clamp(-Vector2.ONE, Vector2.ONE)
	right = right.clamp(-Vector2.ONE, Vector2.ONE)
	var state := PackedInt32Array([
		buttons, triggers.x, triggers.y,
		int(left.x * STICK_MAX), int(left.y * STICK_MAX),
		int(right.x * STICK_MAX), int(right.y * STICK_MAX),
	])
	if state == _state:
		return
	_state = state
	resend()
	held_changed.emit(held())
