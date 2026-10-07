extends "res://tests/test_case.gd"
## The tank editor: entering and leaving edit mode, editing cards, and the
## preset save/load cycle. Drives the same methods the panel buttons call.

const PRESET := "Linguini editor test"


func _main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add(main)
	await tree.process_frame
	return main


func test_edit_mode() -> void:
	var main := await _main()
	main.set_mode(main.Mode.SWIM)
	main.open_editor()
	var editor: TankEditor = main.editor
	check(main.mode == main.Mode.EDIT and editor.is_open(), "the editor opens")
	check(not main.cards.enabled, "cards are released while editing")
	check(not main.fish.is_physics_processing(), "the fish holds still")
	editor.close()
	check(main.mode == main.Mode.SWIM and not editor.is_open(), "closing returns to swimming")
	check(main.fish.is_physics_processing(), "and the fish swims again")
	main.queue_free()


func test_editing_cards() -> void:
	var main := await _main()
	main.open_editor()
	var editor: TankEditor = main.editor
	var cards: CardSystem = main.cards
	var before := cards.cards.size()

	editor._on_add_card()
	check(cards.cards.size() == before + 1 and editor.selected != null, "Add card adds and selects a card")
	check(editor.dirty, "the layout is marked unsaved")

	editor._on_hold_input_toggled(true, "B")
	check(editor.selected.binding.inputs == PackedStringArray(["A", "B"]), "toggling B makes an A + B combo (%s)" % editor.selected.binding.inputs)

	editor._on_kind_changed(CardBinding.Kind.SEQUENCE)
	var seq := editor.selected.binding
	check(seq.kind == CardBinding.Kind.SEQUENCE and seq.steps.size() == 2, "switching to a sequence turns the inputs into steps")
	editor._on_step_changed(1, "at", 300)
	check(editor.selected.binding.duration_ms() == 380, "editing a step's start moves it (%d ms)" % editor.selected.binding.duration_ms())

	editor._on_kind_changed(CardBinding.Kind.TOGGLE)
	var toggle := editor.selected.binding
	check(toggle.kind == CardBinding.Kind.TOGGLE and toggle.inputs == PackedStringArray(["A", "B"]), "switching to a toggle keeps the inputs (%s)" % toggle.inputs)
	editor._on_hold_input_toggled(false, "B")
	check(editor.selected.binding.kind == CardBinding.Kind.TOGGLE and editor.selected.binding.inputs == PackedStringArray(["A"]), "a toggle's inputs can be edited")

	editor._on_kind_changed(CardBinding.Kind.HOLD)
	editor._on_hold_input_toggled(true, "B")
	editor._on_hold_input_toggled(false, "A")
	editor._on_hold_input_toggled(false, "B")
	check(not editor.selected.binding.inputs.is_empty(), "a hold card can't be left with no inputs")

	editor._move_selected(Vector3(5, 5, 5))
	var p: Vector3 = editor.selected.position
	check(editor.water_local.grow(0.001).has_point(p) and p.z < cards.front_z, "cards can't be dragged out of the water (%s)" % p)

	editor._on_duplicate()
	check(cards.cards.size() == before + 2, "Duplicate adds a copy")
	editor._on_delete_card()
	check(cards.cards.size() == before + 1 and editor.selected == null, "Delete card removes it")
	main.queue_free()


func test_preset_cycle() -> void:
	var original := Settings.layout_preset()
	LayoutPresets.delete(PRESET)
	var main := await _main()
	main.open_editor()
	var editor: TankEditor = main.editor
	var cards: CardSystem = main.cards
	editor.load_preset(LayoutPresets.DEFAULT)
	var default_count := cards.cards.size()

	editor._on_add_card()
	editor._on_kind_changed(CardBinding.Kind.SEQUENCE)
	editor._save_as_name.text = PRESET
	editor._on_save_as()
	check(not editor.dirty and editor.preset_name == PRESET, "Save as saves and switches to the new preset")
	check(Settings.layout_preset() == PRESET, "the app remembers the preset in use")

	editor._on_save()
	check(LayoutPresets.find(PRESET).size() > 0, "Save on a user preset keeps it")

	editor.load_preset(LayoutPresets.DEFAULT)
	check(cards.cards.size() == default_count, "loading Default restores its %d cards" % default_count)
	editor._on_save()
	check(editor._status.text.contains("built in"), "Save on a built-in preset asks for Save as")

	editor.load_preset(PRESET)
	var sequences := cards.cards.filter(func(c: FlashCard) -> bool: return c.binding.kind == CardBinding.Kind.SEQUENCE)
	check(cards.cards.size() == default_count + 1 and sequences.size() == 1, "the saved preset loads back with its sequence card")

	# Unsaved changes need a second click to throw away.
	editor._on_add_card()
	editor._preset_list.select(0)
	editor._on_load()
	check(editor.dirty and editor.preset_name == PRESET, "the first Load click only warns")
	editor._on_load()
	check(not editor.dirty and editor.preset_name == LayoutPresets.DEFAULT, "the second one loads")

	LayoutPresets.delete(PRESET)
	Settings.set_layout_preset(original)
	main.queue_free()


## The card panel names its inputs in the button art in use, and follows it
## when the art changes with the panel open.
func test_inputs_named_in_the_button_art() -> void:
	var main := await _main()
	main.open_editor()
	var editor: TankEditor = main.editor
	var was: String = Glyphs.setting
	Glyphs.set_setting("xbox", false)
	editor._select(main.cards.cards[0])
	var names := func() -> Dictionary:
		var out := {}
		for b: Button in editor._card_box.find_children("*", "Button", true, false):
			if CardSystem.INPUTS.has(b.tooltip_text):
				out[b.tooltip_text] = b.text
		return out
	var xbox: Dictionary = names.call()
	check(xbox.get("BACK") == "VIEW" and xbox.get("START") == "MENU" and xbox.get("LB") == "LB", "Xbox names: %s" % xbox)
	Glyphs.set_setting("nintendo", false)
	await tree.process_frame
	var nintendo: Dictionary = names.call()
	check(nintendo.get("BACK") == "−" and nintendo.get("START") == "+", "Nintendo uses − and + (%s, %s)" % [nintendo.get("BACK"), nintendo.get("START")])
	check(nintendo.get("LB") == "L" and nintendo.get("RT") == "ZR" and nintendo.get("A") == "B", "and L, ZR, and its own face letters")
	Glyphs.set_setting(was, false)
	main.queue_free()
