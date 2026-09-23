extends "res://tests/test_case.gd"
## Flash cards: zone geometry, press/hold/release timing, combos, toggles,
## sequences, layouts and presets, and the controller state sent to the host.

const DT := 1.0 / 120.0


class FakeClient:
	extends RefCounted
	var sent: Array[PackedInt32Array] = []

	func send_controller_state(b: int, lt: int, rt: int, lx: int, ly: int, rx: int, ry: int) -> void:
		sent.append(PackedInt32Array([b, lt, rt, lx, ly, rx, ry]))

	func last() -> PackedInt32Array:
		return sent[-1] if not sent.is_empty() else PackedInt32Array([0, 0, 0, 0, 0, 0, 0])


func _system(layout := "res://data/layouts/default.json") -> Array:
	var cards := CardSystem.new()
	var client := FakeClient.new()
	cards.client = client
	cards.front_z = 0.25
	add(cards)
	cards.set_physics_process(false)
	if layout != "":
		cards.load_layout(layout)
	return [cards, client]


## The card that holds exactly `ids`.
func _card(cards: CardSystem, ids: Variant) -> FlashCard:
	var want := PackedStringArray([ids] if ids is String else ids)
	for c in cards.cards:
		if c.binding.kind == CardBinding.Kind.HOLD and c.binding.inputs == want:
			return c
	return null


## A point just in front of a card, halfway to the glass.
func _in_front(card: FlashCard) -> Vector3:
	return Vector3(card.position.x, card.position.y, (card.position.z + 0.25) / 2.0)


func _hold(cards: CardSystem, pos: Vector3, seconds: float) -> void:
	for i in int(seconds / DT):
		cards.update(pos, DT)


func test_press_hold_and_release() -> void:
	var s := _system()
	var cards: CardSystem = s[0]
	var client: FakeClient = s[1]
	var a := _card(cards, "A")
	_hold(cards, _in_front(a), 1.0)
	check(client.last()[0] == CardSystem.BUTTON_FLAGS.A, "A pressed while the fish is in front of it")
	check(client.sent.size() == 1, "state is sent once on change, not every frame (%d sends)" % client.sent.size())

	var away := Vector3(0.0, 0.42, 0.2) # open water between the left stick and the top row
	_hold(cards, away, 0.1)
	check(client.last()[0] == CardSystem.BUTTON_FLAGS.A, "A still held just after leaving (debounce)")
	_hold(cards, away, 0.1)
	check(client.last()[0] == 0, "A released once the fish has been away for %.2f s" % CardSystem.RELEASE_DELAY)
	cards.queue_free()


func test_behind_card_does_nothing() -> void:
	var s := _system()
	var cards: CardSystem = s[0]
	var client: FakeClient = s[1]
	var r_up := _card(cards, "R_UP")
	_hold(cards, r_up.position - Vector3(0, 0, 0.06), 0.5)
	check(client.last()[0] == 0 and client.last()[6] == 0, "a fish behind a card doesn't press it")
	cards.queue_free()


func test_only_the_fish_centre_counts() -> void:
	var s := _system()
	var cards: CardSystem = s[0]
	var client: FakeClient = s[1]
	var a := _card(cards, "A")
	var zone := cards.zone_for(a.position)
	# Centred just outside the zone, the fish's body overlaps it but its centre doesn't.
	_hold(cards, Vector3(zone.end.x + 0.01, a.position.y, 0.1), 0.5)
	check(client.last()[0] == 0, "a fish centred 1 cm outside A's zone doesn't press it")
	_hold(cards, Vector3(zone.end.x - 0.005, a.position.y, 0.1), 0.1)
	check(client.last()[0] == CardSystem.BUTTON_FLAGS.A, "A presses once the fish's centre is inside")
	cards.queue_free()


func test_hysteresis_prevents_flicker() -> void:
	var s := _system()
	var cards: CardSystem = s[0]
	var client: FakeClient = s[1]
	var b := _card(cards, "B")
	_hold(cards, _in_front(b), 0.2)
	var zone := cards.zone_for(b.position)
	# Drift back and forth across the edge, within the hysteresis margin.
	var edge_x := zone.position.x
	for i in 20:
		_hold(cards, Vector3(edge_x - 0.01, b.position.y, 0.1), 0.05)
		_hold(cards, Vector3(edge_x + 0.005, b.position.y, 0.1), 0.05)
	check(client.sent.size() == 1, "no flicker at the zone edge (%d sends)" % client.sent.size())
	cards.queue_free()


func test_sticks_and_triggers() -> void:
	var s := _system()
	var cards: CardSystem = s[0]
	var client: FakeClient = s[1]
	_hold(cards, _in_front(_card(cards, "L_UP")), 0.2)
	check(client.last()[3] == 0 and client.last()[4] == CardSystem.STICK_MAX, "L_UP pushes the left stick fully up")

	_hold(cards, _in_front(_card(cards, "RT")), 0.5)
	check(client.last()[2] == CardSystem.TRIGGER_MAX and client.last()[1] == 0, "RT pulls the right trigger fully")
	cards.queue_free()


func test_default_layout_is_unambiguous() -> void:
	var s := _system()
	var cards: CardSystem = s[0]
	check(cards.cards.size() == CardSystem.INPUTS.size(), "default layout: one card per input (%d cards)" % cards.cards.size())
	var ids := {}
	for card in cards.cards:
		var n := card.binding.display_name()
		if card.binding.inputs.size() == 1:
			ids[card.input_id] = true
		var zone := cards.zone_for(card.position)
		check(zone.position.y >= 0.03 - 0.01 and zone.end.y <= 0.56 + 0.01, "%s zone is within the water" % n)
		check(zone.position.x >= -0.6 and zone.end.x <= 0.6, "%s zone is within the tank" % n)
	check(ids.size() == CardSystem.INPUTS.size(), "every input has its own card")

	# Centred in front of any card, the fish presses exactly that card's inputs.
	for card in cards.cards:
		cards.set_enabled(false)
		cards.set_enabled(true)
		cards.update(_in_front(card), DT)
		var held := cards.held()
		var want := card.binding.inputs
		var same := held.size() == want.size() and Array(want).all(func(id: String) -> bool: return id in held)
		check(same, "in front of %s holds only %s (%s)" % [card.binding.display_name(), want, held])
	cards.queue_free()


## A left stick laid out as a 3x3 grid with combo cards on the diagonals, and
## one right-stick diagonal.
func _diagonal_system() -> Array:
	var s := _system("")
	var cards: CardSystem = s[0]
	var grid := {
		"L_UP": [0, 1], "L_DOWN": [0, -1], "L_LEFT": [-1, 0], "L_RIGHT": [1, 0],
		"L_UP+L_LEFT": [-1, 1], "L_UP+L_RIGHT": [1, 1], "L_DOWN+L_LEFT": [-1, -1], "L_DOWN+L_RIGHT": [1, -1],
	}
	var entries := []
	for ids: String in grid:
		var cell: Array = grid[ids]
		entries.append({"inputs": ids.split("+"), "position": [-0.4 + cell[0] * 0.115, 0.15 + cell[1] * 0.08, -0.225]})
	entries.append({"inputs": ["R_DOWN", "R_LEFT"], "position": [0.3, 0.15, -0.225]})
	cards.load_layout_data({"cards": entries})
	return s


func test_diagonal_combo() -> void:
	var s := _diagonal_system()
	var cards: CardSystem = s[0]
	var client: FakeClient = s[1]
	_hold(cards, _in_front(_card(cards, ["L_UP", "L_RIGHT"])), 0.2)
	var st := client.last()
	check(st[3] == CardSystem.STICK_MAX and st[4] == CardSystem.STICK_MAX, "the up-right card pushes the left stick up and right (%s)" % st)
	_hold(cards, _in_front(_card(cards, ["R_DOWN", "R_LEFT"])), 0.5)
	st = client.last()
	check(st[5] == -CardSystem.STICK_MAX and st[6] == -CardSystem.STICK_MAX and st[3] == 0, "down-left on the right stick (%s)" % st)

	var up := _card(cards, "L_UP").position
	var right := _card(cards, "L_RIGHT").position
	var corner := Vector3(right.x - CardSystem.CARD_SIZE.x / 2, up.y - CardSystem.CARD_SIZE.y / 2, 0.1)
	cards.set_enabled(false) # start with nothing held, so no hysteresis margin applies
	cards.set_enabled(true)
	_hold(cards, corner, 0.5)
	check(cards.held().is_empty(), "the gap between a stick arm and its diagonal presses nothing (%s)" % cards.held())
	cards.queue_free()


func _toggle_system() -> Array:
	var s := _system("")
	var cards: CardSystem = s[0]
	cards.load_layout_data({"cards": [
		{"inputs": ["LT"], "toggle": true, "position": [0.0, 0.2, -0.225]},
		{"inputs": ["A"], "position": [0.3, 0.2, -0.225]},
	]})
	return s


func test_toggle_switches_on_each_arrival() -> void:
	var s := _toggle_system()
	var cards: CardSystem = s[0]
	var client: FakeClient = s[1]
	var toggle := cards.cards[0]
	var away := Vector3(-0.4, 0.45, 0.2)
	check(toggle.binding.kind == CardBinding.Kind.TOGGLE, "a card with \"toggle\": true loads as a toggle")

	_hold(cards, _in_front(toggle), 0.3)
	check(client.last()[1] == CardSystem.TRIGGER_MAX, "arriving switches LT on")
	_hold(cards, away, 1.0)
	check(client.last()[1] == CardSystem.TRIGGER_MAX and toggle.latched, "LT stays held after the fish leaves")
	_hold(cards, _in_front(cards.cards[1]), 0.3)
	check(client.last()[0] == CardSystem.BUTTON_FLAGS.A and client.last()[1] == CardSystem.TRIGGER_MAX, "other cards press on top of it")
	check(toggle in cards.engaged_cards(), "a toggled-on card counts as engaged")

	_hold(cards, away, 0.3)
	_hold(cards, _in_front(toggle), 0.3)
	check(client.last()[1] == 0 and not toggle.latched, "arriving again switches LT off")
	_hold(cards, away, 1.0)
	check(client.last()[1] == 0, "and it stays off after the fish leaves")

	# Lingering or drifting along the edge doesn't flip it back.
	_hold(cards, _in_front(toggle), 0.3)
	var zone := cards.zone_for(toggle.position)
	for i in 10:
		_hold(cards, Vector3(zone.position.x - 0.01, toggle.position.y, 0.1), 0.05)
		_hold(cards, Vector3(zone.position.x + 0.005, toggle.position.y, 0.1), 0.05)
	check(client.last()[1] == CardSystem.TRIGGER_MAX, "one visit is one switch, however long the fish stays")

	cards.enabled = false
	check(client.last() == PackedInt32Array([0, 0, 0, 0, 0, 0, 0]) and not toggle.latched, "menus switch toggles off")
	cards.enabled = true
	_hold(cards, away, 0.3)
	check(client.last()[1] == 0, "and they stay off afterwards")
	cards.queue_free()


func _sequence_system() -> Array:
	var s := _system("")
	var cards: CardSystem = s[0]
	cards.load_layout_data({"cards": [
		{"label": "Roll + attack", "position": [0.0, 0.2, -0.225], "sequence": [
			{"input": "B", "at": 0, "hold": 80},
			{"input": "RB", "at": 180, "hold": 80},
		]},
	]})
	return s


func _pressed_at(cards: CardSystem, pos: Vector3, from_s: float, to_s: float) -> Array:
	var out := []
	var t := from_s
	while t < to_s - 0.0001:
		cards.update(pos, DT)
		t += DT
		out.append([t, cards.held().duplicate()])
	return out


func test_sequence_plays_once_on_arrival() -> void:
	var s := _sequence_system()
	var cards: CardSystem = s[0]
	var card := cards.cards[0]
	var at := _in_front(card)
	var timeline := _pressed_at(cards, at, 0.0, 1.0)
	var saw := func(input: String, from_s: float, to_s: float) -> bool:
		for sample: Array in timeline:
			if sample[0] > from_s and sample[0] < to_s and input in sample[1]:
				return true
		return false
	check(saw.call("B", 0.0, 0.07), "B is pressed at the start")
	check(not saw.call("B", 0.1, 1.0), "B is released after 80 ms")
	check(not saw.call("RB", 0.1, 0.17), "gap before RB")
	check(saw.call("RB", 0.19, 0.25), "RB is pressed at 180 ms")
	check(not saw.call("RB", 0.28, 1.0), "RB is released after 80 ms")
	check(cards.held().is_empty() and card.active, "staying in front doesn't replay it")

	# Leave (past the release delay) and come back: it plays again.
	_pressed_at(cards, Vector3(0.4, 0.45, 0.2), 0.0, 0.3)
	var again := _pressed_at(cards, at, 0.0, 0.05)
	check(again.any(func(sample: Array) -> bool: return "B" in sample[1]), "arriving again replays the sequence")
	cards.queue_free()


func test_sequence_finishes_after_the_fish_leaves() -> void:
	var s := _sequence_system()
	var cards: CardSystem = s[0]
	_pressed_at(cards, _in_front(cards.cards[0]), 0.0, 0.03)
	var after := _pressed_at(cards, Vector3(0.4, 0.45, 0.2), 0.0, 0.4)
	check(after.any(func(sample: Array) -> bool: return "RB" in sample[1]), "the sequence still reaches RB after the fish swims off")
	check(cards.held().is_empty(), "and ends released")
	cards.queue_free()


func test_layout_round_trip() -> void:
	var s := _system()
	var cards: CardSystem = s[0]
	var seq := CardBinding.sequence([{"input": "A", "at": 0, "hold": 50}], "Jump")
	cards.add_card(seq, Vector3(0.0, 0.3, -0.05))
	cards.add_card(CardBinding.toggle(["LT", "L3"]), Vector3(0.0, 0.4, -0.05))
	var data := cards.layout_data("Round trip")
	var copy := CardSystem.new()
	add(copy)
	copy.load_layout_data(JSON.parse_string(JSON.stringify(data)))
	check(copy.cards.size() == cards.cards.size(), "same number of cards (%d vs %d)" % [copy.cards.size(), cards.cards.size()])
	for i in mini(copy.cards.size(), cards.cards.size()):
		var a := cards.cards[i]
		var b := copy.cards[i]
		check(a.binding.to_dict() == b.binding.to_dict(), "card %d binding survives (%s vs %s)" % [i, a.binding.to_dict(), b.binding.to_dict()])
		check(a.position.distance_to(b.position) < 0.001, "card %d position survives" % i)
	cards.queue_free()
	copy.queue_free()


func test_invalid_bindings_are_skipped() -> void:
	check(CardBinding.from_dict({"inputs": []}) == null, "no inputs")
	check(CardBinding.from_dict({"inputs": ["TURBO"]}) == null, "unknown input")
	check(CardBinding.from_dict({"inputs": [], "toggle": true}) == null, "toggle with no inputs")
	check(CardBinding.from_dict({"sequence": [{"input": "A", "at": 0, "hold": 5}]}) == null, "step too short")
	check(CardBinding.from_dict({"sequence": [{"input": "A", "at": 20000, "hold": 50}]}) == null, "too long")
	check(CardBinding.from_dict({"input": "A"}) != null, "older single-input cards still load")


func test_presets() -> void:
	var name := "Linguini test preset"
	LayoutPresets.delete(name)
	check(not LayoutPresets.find(LayoutPresets.DEFAULT).is_empty(), "the Default preset is built in")
	check(LayoutPresets.save(LayoutPresets.DEFAULT, {"cards": []}) != "", "built-in presets can't be overwritten")
	check(LayoutPresets.delete(LayoutPresets.DEFAULT) != "", "built-in presets can't be deleted")

	var data := {"cards": [{"inputs": ["A", "B"], "position": [0.0, 0.2, -0.2]}]}
	check(LayoutPresets.save(name, data) == "", "saving a user preset works")
	var found := LayoutPresets.find(name)
	check(not found.is_empty() and not found.builtin, "it's listed as a user preset")
	var loaded := LayoutPresets.load_data(name)
	check(loaded.get("cards", []) == data.cards, "it loads back the same cards")
	check(LayoutPresets.save(name, {"cards": []}) == "" and LayoutPresets.load_data(name).cards.is_empty(), "saving again overwrites it")
	check(LayoutPresets.delete(name) == "" and LayoutPresets.find(name).is_empty(), "it can be deleted")


func test_disabling_releases_everything() -> void:
	var s := _system()
	var cards: CardSystem = s[0]
	var client: FakeClient = s[1]
	_hold(cards, _in_front(_card(cards, "X")), 0.2)
	cards.enabled = false
	check(client.last() == PackedInt32Array([0, 0, 0, 0, 0, 0, 0]), "menus release all buttons on the host")
	cards.queue_free()


func test_flags_match_native_constants() -> void:
	if not ClassDB.class_exists("MoonlightClient"):
		check(false, "native extension not loaded")
		return
	var native := {
		"A": "BUTTON_A", "B": "BUTTON_B", "X": "BUTTON_X", "Y": "BUTTON_Y",
		"DPAD_UP": "BUTTON_DPAD_UP", "DPAD_DOWN": "BUTTON_DPAD_DOWN",
		"DPAD_LEFT": "BUTTON_DPAD_LEFT", "DPAD_RIGHT": "BUTTON_DPAD_RIGHT",
		"START": "BUTTON_START", "BACK": "BUTTON_BACK", "L3": "BUTTON_L3", "R3": "BUTTON_R3",
		"LB": "BUTTON_LB", "RB": "BUTTON_RB",
	}
	for id in native:
		var value := ClassDB.class_get_integer_constant("MoonlightClient", native[id])
		check(CardSystem.BUTTON_FLAGS[id] == value, "%s flag matches Limelight.h" % id)
