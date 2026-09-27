extends Node
## Renders a sheet of card faces to a PNG, for checking how cards print:
##   godot --path godot -- --tool=card_faces OUT.png
## (Needs a window: nothing draws headless.)

## Positional command-line arguments, set by main.gd before the tool starts.
var args := PackedStringArray()

const CARD_SIZE := Vector2(0.11, 0.08)
const COLUMNS := 4


func _bindings() -> Array[CardBinding]:
	var s := func(ids: Array) -> CardBinding:
		var steps := []
		for i in ids.size():
			steps.append({"input": ids[i], "at": i * 120, "hold": 80})
		return CardBinding.sequence(steps)
	var named: CardBinding = s.call(["B", "B", "A"])
	named.label = "Roll"
	var out: Array[CardBinding] = [
		s.call(["A", "B", "A", "B"]), s.call(["LB", "RB", "LT", "RT"]), s.call(["L_UP", "L_DOWN", "A"]),
		s.call(["X", "Y", "LB", "START", "BACK"]), s.call(["DPAD_UP", "DPAD_UP", "DPAD_DOWN", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT"]),
		named, CardBinding.hold(["RB", "A"]), CardBinding.tap(["DPAD_DOWN"]), CardBinding.tap(["A"]),
	]
	return out


func _ready() -> void:
	var path := args[0] if args.size() > 0 else "user://card_faces.png"
	var bindings := _bindings()
	var textures: Array[Texture2D] = []
	textures.resize(bindings.size())
	var left := [bindings.size()]
	for i in bindings.size():
		CardFace.request(bindings[i], FlashCard.SEQUENCE_COLOR if bindings[i].kind == CardBinding.Kind.SEQUENCE else Color(0.3, 0.6, 0.9),
			CARD_SIZE, func(tex: Texture2D) -> void:
				textures[i] = tex
				left[0] -= 1)
	while left[0] > 0:
		await get_tree().process_frame
	var cell := textures[0].get_image().get_size()
	var rows := ceili(float(textures.size()) / COLUMNS)
	var sheet := Image.create(cell.x * COLUMNS, cell.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.2, 0.22))
	for i in textures.size():
		var img := textures[i].get_image()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i % COLUMNS * cell.x, i / COLUMNS * cell.y))
	sheet.save_png(path)
	print("Saved card faces to ", path)
	get_tree().quit()
