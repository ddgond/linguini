extends "res://tests/test_case.gd"
## Flash cards: zone geometry, press/hold/release timing and the controller
## state sent to the host.

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


func _card(cards: CardSystem, id: String) -> FlashCard:
	for c in cards.cards:
		if c.input_id == id:
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

	var away := Vector3(0.0, 0.42, 0.2) # open water between START/BACK and the shoulders
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


func test_hysteresis_prevents_flicker() -> void:
	var s := _system()
	var cards: CardSystem = s[0]
	var client: FakeClient = s[1]
	var b := _card(cards, "B")
	_hold(cards, _in_front(b), 0.2)
	var zone := cards.zone_for(b.position)
	# Drift back and forth across the edge, within the hysteresis margin.
	var edge_x := zone.position.x - CardSystem.FISH_RADIUS
	for i in 20:
		_hold(cards, Vector3(edge_x - 0.01, b.position.y, 0.1), 0.05)
		_hold(cards, Vector3(edge_x + 0.005, b.position.y, 0.1), 0.05)
	check(client.sent.size() == 1, "no flicker at the zone edge (%d sends)" % client.sent.size())
	cards.queue_free()


func test_sticks_triggers_and_diagonals() -> void:
	var s := _system()
	var cards: CardSystem = s[0]
	var client: FakeClient = s[1]
	_hold(cards, _in_front(_card(cards, "L_UP")), 0.2)
	check(client.last()[3] == 0 and client.last()[4] == CardSystem.STICK_MAX, "L_UP pushes the left stick fully up")

	var up := _card(cards, "L_UP").position
	var right := _card(cards, "L_RIGHT").position
	var corner := Vector3(right.x - CardSystem.CARD_SIZE.x / 2, up.y - CardSystem.CARD_SIZE.y / 2, 0.1)
	_hold(cards, corner, 0.5)
	var st := client.last()
	check(st[3] == CardSystem.STICK_MAX and st[4] == CardSystem.STICK_MAX, "between L_UP and L_RIGHT: up-right diagonal (%s)" % st)
	check(cards.held().size() == 2, "a diagonal holds exactly the two arms (%s)" % cards.held())

	_hold(cards, _in_front(_card(cards, "RT")), 0.5)
	check(client.last()[2] == CardSystem.TRIGGER_MAX and client.last()[1] == 0, "RT pulls the right trigger fully")
	cards.queue_free()


func test_default_layout_is_unambiguous() -> void:
	var s := _system()
	var cards: CardSystem = s[0]
	check(cards.cards.size() == 24, "default layout has the full controller (%d cards)" % cards.cards.size())
	var ids := {}
	for card in cards.cards:
		ids[card.input_id] = true
		var zone := cards.zone_for(card.position)
		check(zone.position.y >= 0.03 - 0.01 and zone.end.y <= 0.56 + 0.01, "%s zone is within the water" % card.input_id)
		check(zone.position.x >= -0.6 and zone.end.x <= 0.6, "%s zone is within the tank" % card.input_id)
	check(ids.size() == CardSystem.INPUTS.size(), "every input has a card")

	# Centred in front of any card, the fish presses exactly that card.
	for card in cards.cards:
		cards.set_enabled(false)
		cards.set_enabled(true)
		cards.update(_in_front(card), DT)
		var held := cards.held()
		check(held.size() == 1 and held[0] == card.input_id, "in front of %s holds only it (%s)" % [card.input_id, held])
	cards.queue_free()


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
