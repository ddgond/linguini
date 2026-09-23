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
## flicker the button.
##
## What a card sends is its CardBinding. A HOLD card presses its inputs for as
## long as the fish stays; a SEQUENCE card plays its macro once when the fish
## arrives, finishing even if the fish swims off. Arriving again replays it.
## A TOGGLE card switches its inputs on when the fish arrives and keeps them
## held after it leaves, until it arrives again. Menus switch toggles off.

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

const SHORT_NAMES := {
	"DPAD_UP": "D↑", "DPAD_DOWN": "D↓", "DPAD_LEFT": "D←", "DPAD_RIGHT": "D→",
	"L_UP": "L↑", "L_DOWN": "L↓", "L_LEFT": "L←", "L_RIGHT": "L→",
	"R_UP": "R↑", "R_DOWN": "R↓", "R_LEFT": "R←", "R_RIGHT": "R→",
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
## Milliseconds into each card's sequence, or -1 when it isn't playing.
var _play_ms: Array[float] = []
## Whether each toggle card is switched on.
var _latched: Array[bool] = []
var _pressed := PackedStringArray()
var _state := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
var _show_zones := false


static func short_name(id: String) -> String:
	return SHORT_NAMES.get(id, INPUTS[id].get("label", id))


func load_layout(path: String) -> bool:
	var data := LayoutPresets.read(path)
	if data.is_empty():
		push_error("CardSystem: can't read layout " + path)
		return false
	load_layout_data(data)
	return true


func load_layout_data(data: Dictionary) -> void:
	clear()
	for entry: Dictionary in data.get("cards", []):
		var binding := CardBinding.from_dict(entry)
		var p: Array = entry.get("position", [])
		if binding == null or p.size() != 3:
			continue
		add_card(binding, Vector3(p[0], p[1], p[2]))


## The current cards as layout data (see CardBinding for the card format).
func layout_data(layout_name: String) -> Dictionary:
	var out := []
	for card in cards:
		var entry := card.binding.to_dict()
		var p := card.position
		entry.position = [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]
		out.append(entry)
	return {"name": layout_name, "cards": out}


func clear() -> void:
	for card in cards:
		remove_child(card)
		card.queue_free()
	cards.clear()
	_zones.clear()
	_release_timers.clear()
	_play_ms.clear()
	_latched.clear()
	_publish()


func add_card(binding: CardBinding, pos: Vector3) -> FlashCard:
	var card := FlashCard.new(binding, CARD_SIZE)
	card.position = pos
	add_child(card)
	cards.append(card)
	_zones.append(zone_for(pos))
	_release_timers.append(0.0)
	_play_ms.append(-1.0)
	_latched.append(false)
	if _show_zones:
		card.show_zone(_zones[-1], true)
	return card


func remove_card(card: FlashCard) -> void:
	var i := cards.find(card)
	if i < 0:
		return
	cards.remove_at(i)
	_zones.remove_at(i)
	_release_timers.remove_at(i)
	_play_ms.remove_at(i)
	_latched.remove_at(i)
	remove_child(card)
	card.queue_free()
	_publish()


func move_card(card: FlashCard, pos: Vector3) -> void:
	var i := cards.find(card)
	if i < 0:
		return
	card.position = pos
	_zones[i] = zone_for(pos)
	card.show_zone(_zones[i], _show_zones)


## Replaces a card's binding; returns the new card node (faces are rebuilt).
func rebind_card(card: FlashCard, binding: CardBinding) -> FlashCard:
	var i := cards.find(card)
	if i < 0:
		return card
	var fresh := FlashCard.new(binding, CARD_SIZE)
	fresh.position = card.position
	add_child(fresh)
	remove_child(card)
	card.queue_free()
	cards[i] = fresh
	_play_ms[i] = -1.0
	_latched[i] = false
	if _show_zones:
		fresh.show_zone(_zones[i], true)
	_publish()
	return fresh


## Where cards may sit: inside the water, clear of the glass.
func clamp_position(pos: Vector3, water: AABB) -> Vector3:
	var half := CARD_SIZE * 0.5
	return Vector3(
		clampf(pos.x, water.position.x + half.x, water.end.x - half.x),
		clampf(pos.y, water.position.y + half.y, water.end.y - half.y),
		clampf(pos.z, water.position.z + 0.025, front_z - 0.05))


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
			_play_ms[i] = -1.0
			_latched[i] = false
			cards[i].latched = false
		_publish()


func _physics_process(delta: float) -> void:
	if fish == null or not enabled:
		return
	update(to_local(fish.global_position), delta)


## Advances the press/release logic for the fish's centre at `fish_pos` (this node's space).
func update(fish_pos: Vector3, delta: float) -> void:
	for i in cards.size():
		var card := cards[i]
		var kind := card.binding.kind
		if _play_ms[i] >= 0.0:
			_play_ms[i] += delta * 1000.0
			if _play_ms[i] >= card.binding.duration_ms():
				_play_ms[i] = -1.0
		var zone := _zones[i].grow(HYSTERESIS) if card.active else _zones[i]
		if zone.has_point(fish_pos):
			if not card.active:
				if kind == CardBinding.Kind.SEQUENCE:
					_play_ms[i] = 0.0
				elif kind == CardBinding.Kind.TOGGLE:
					_latched[i] = not _latched[i]
			card.active = true
			_release_timers[i] = RELEASE_DELAY
		elif card.active:
			_release_timers[i] -= delta
			if _release_timers[i] <= 0.0:
				card.active = false
		card.playing = _play_ms[i] >= 0.0
		card.latched = _latched[i]
	_publish()


## Resends the current state, e.g. when a stream (re)starts.
func resend() -> void:
	if client:
		client.send_controller_state(_state[0], _state[1], _state[2], _state[3], _state[4], _state[5], _state[6])


## Inputs currently pressed on the host, from all cards.
func held() -> PackedStringArray:
	return _pressed


## Cards the fish is in front of, whose sequence is still playing, or that
## are toggled on.
func engaged_cards() -> Array[FlashCard]:
	var out: Array[FlashCard] = []
	for i in cards.size():
		if cards[i].active or _play_ms[i] >= 0.0 or _latched[i]:
			out.append(cards[i])
	return out


## [buttons, left_trigger, right_trigger, left_x, left_y, right_x, right_y]
func controller_state() -> PackedInt32Array:
	return _state


func toggle_zones() -> void:
	set_zones_visible(not _show_zones)


func set_zones_visible(value: bool) -> void:
	_show_zones = value
	for i in cards.size():
		cards[i].show_zone(_zones[i], _show_zones)


func _publish() -> void:
	var pressed := PackedStringArray()
	for i in cards.size():
		var card := cards[i]
		var ids := PackedStringArray()
		match card.binding.kind:
			CardBinding.Kind.SEQUENCE:
				if _play_ms[i] >= 0.0:
					ids = card.binding.inputs_at(_play_ms[i])
			CardBinding.Kind.TOGGLE:
				if _latched[i]:
					ids = card.binding.inputs
			_:
				if card.active:
					ids = card.binding.inputs
		for id in ids:
			if id not in pressed:
				pressed.append(id)
	var state := compose_state(pressed)
	if state == _state:
		return
	_state = state
	_pressed = pressed
	resend()
	held_changed.emit(_pressed)


## Controller state for a set of pressed inputs. Opposite stick directions
## cancel out; adjacent ones make a diagonal.
static func compose_state(pressed: PackedStringArray) -> PackedInt32Array:
	var buttons := 0
	var triggers := Vector2i.ZERO
	var left := Vector2.ZERO
	var right := Vector2.ZERO
	for id in pressed:
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
	return PackedInt32Array([
		buttons, triggers.x, triggers.y,
		int(left.x * STICK_MAX), int(left.y * STICK_MAX),
		int(right.x * STICK_MAX), int(right.y * STICK_MAX),
	])
