class_name CardFace
extends Control
## The printed side of a flash card, drawn in 2D and baked into a texture:
## a coloured header band with the card's corner label, then the glyph (a
## button badge, an arrow, a shoulder pill) or, for combos and sequences, the
## card's name over a row of glyph chips. A little wear makes each one its own.
##
## CardFace.request() renders each distinct face once (per glyph set) and
## hands back a mipmapped texture; identical cards share it.

const WIDTH := 512
const INK := Color(0.17, 0.17, 0.2)
const PAPER := Color(0.97, 0.955, 0.91)

var binding: CardBinding
var color: Color
var set_name := "xbox"
var aspect := 0.72
var seed_value := 0

static var _cache := {}
static var _waiting := {}
static var _host: Node


## Calls `done(texture)` with the face for `binding`, now if it's cached or
## once it's been drawn. `card_size` is in metres (for the aspect ratio).
static func request(p_binding: CardBinding, p_color: Color, card_size: Vector2, done: Callable) -> void:
	var key := "%s|%s|%s|%.3f" % [Glyphs.current, JSON.stringify(p_binding.to_dict()), p_color.to_html(), card_size.y / card_size.x]
	if _cache.has(key):
		done.call(_cache[key])
		return
	if _waiting.has(key):
		_waiting[key].append(done)
		return
	_waiting[key] = [done]
	if DisplayServer.get_name() == "headless":
		# Nothing draws headless, so frame_post_draw never comes.
		_finish(key, _plain_paper())
		return
	var face := CardFace.new()
	face.binding = p_binding
	face.color = p_color
	face.set_name = Glyphs.current
	face.aspect = card_size.y / card_size.x
	face.seed_value = hash(key)
	_render(key, face)


static func _render(key: String, face: CardFace) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if _host == null or not is_instance_valid(_host):
		_host = Node.new()
		_host.name = "CardFaces"
		tree.root.add_child.call_deferred(_host)
		await tree.process_frame
	var vp := SubViewport.new()
	vp.size = Vector2i(WIDTH, int(WIDTH * face.aspect))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	face.size = Vector2(vp.size)
	vp.add_child(face)
	_host.add_child(vp)
	await RenderingServer.frame_post_draw
	var texture: Texture2D = null
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		texture = ImageTexture.create_from_image(img)
	else:
		texture = _plain_paper()
	vp.queue_free()
	_finish(key, texture)


static func _finish(key: String, texture: Texture2D) -> void:
	_cache[key] = texture
	for done: Callable in _waiting.get(key, []):
		if done.is_valid():
			done.call(texture)
	_waiting.erase(key)


static func _plain_paper() -> Texture2D:
	var plain := Image.create(4, 4, false, Image.FORMAT_RGB8)
	plain.fill(PAPER)
	return ImageTexture.create_from_image(plain)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	# Paper tooth and a little handling wear.
	for i in 500:
		var p := Vector2(rng.randf() * w, rng.randf() * h)
		draw_circle(p, rng.randf_range(0.6, 1.6), Color(0.5, 0.45, 0.35, rng.randf_range(0.01, 0.03)))
	var corner := Vector2(w if rng.randf() < 0.5 else 0.0, h if rng.randf() < 0.5 else 0.0)
	for i in 6:
		draw_circle(corner, w * (0.08 + i * 0.03), Color(0.45, 0.38, 0.28, 0.018))
	if rng.randf() < 0.5:
		var y := h * rng.randf_range(0.35, 0.8)
		draw_line(Vector2(0, y), Vector2(w, y + rng.randf_range(-8, 8)), Color(1, 1, 1, 0.35), 2.0, true)
		draw_line(Vector2(0, y + 2), Vector2(w, y + 2 + rng.randf_range(-8, 8)), Color(0.3, 0.25, 0.2, 0.06), 2.0, true)

	# Header band with the corner label.
	var band := h * 0.2
	draw_rect(Rect2(0, 0, w, band), color)
	draw_rect(Rect2(0, band - 3, w, 3), color.darkened(0.25))
	var ids := binding.all_inputs()
	var info: Dictionary = CardSystem.INPUTS[ids[0]]
	var arrow := FlashCard.combined_arrow(binding)
	var single := binding.kind == CardBinding.Kind.HOLD and ids.size() == 1
	var header := ""
	if binding.kind == CardBinding.Kind.SEQUENCE:
		header = "SEQUENCE · %.1f s" % (binding.duration_ms() / 1000.0)
	elif arrow != Vector2.ZERO:
		header = info.get("caption", "")
	elif single:
		header = info.get("caption", _kind_of(ids[0]))
	else:
		header = "COMBO"
	_text(header, Vector2(w * 0.07, band * 0.7), int(band * 0.52), Color(1, 1, 1, 0.95), 800)
	if single or arrow != Vector2.ZERO:
		var tag := Glyphs.label(ids[0], set_name) if arrow == Vector2.ZERO else _arrow_tag(arrow)
		var tw := UiStyle.font(800).get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(band * 0.52)).x
		_text(tag, Vector2(w * 0.93 - tw, band * 0.7), int(band * 0.52), Color(1, 1, 1, 0.8), 800)

	var body_center := Vector2(w / 2, band + (h - band) * 0.5)
	var body := (h - band) * 0.5
	if arrow != Vector2.ZERO:
		# A pale ring, as printed D-pads and sticks are drawn.
		draw_circle(body_center, body * 0.82, color.lightened(0.75))
		Glyphs.draw_arrow(self, arrow, body_center, body * 0.62, color.darkened(0.1))
	elif single:
		_glyph(ids[0], body_center, body * 0.7)
	else:
		var name_text := binding.display_name() if binding.label != "" else ""
		var chips_y := body_center.y + (body * 0.35 if name_text != "" else 0.0)
		if name_text != "":
			_text_centered(name_text, Vector2(w / 2, body_center.y - body * 0.2), int(body * 0.42), INK, 800, w * 0.88)
		_chips(ids, Vector2(w / 2, chips_y), body * (0.3 if name_text != "" else 0.42))


func _glyph(id: String, center: Vector2, r: float) -> void:
	if Glyphs.FACE[set_name].has(id):
		Glyphs.draw_badge(self, id, center, r, set_name)
	else:
		Glyphs.draw_pill(self, id, center, r * 1.3, CardSystem.INPUTS[id].color, set_name)


## A row of small glyphs joined by + (combo) or › (sequence).
func _chips(ids: PackedStringArray, center: Vector2, r: float) -> void:
	var sep := " › " if binding.kind == CardBinding.Kind.SEQUENCE else " + "
	var n := ids.size()
	var step := minf(r * 3.0, size.x * 0.9 / maxf(n, 1))
	r = minf(r, step * 0.36)
	var x0 := center.x - step * (n - 1) / 2.0
	for i in n:
		var c := Vector2(x0 + step * i, center.y)
		var id := ids[i]
		var info: Dictionary = CardSystem.INPUTS[id]
		if info.has("arrow"):
			draw_circle(c, r, Color(info.color).lightened(0.7))
			Glyphs.draw_arrow(self, info.arrow, c, r * 0.72, Color(info.color).darkened(0.1))
		else:
			_glyph(id, c, r)
		if i < n - 1:
			var s := sep.strip_edges()
			var fs := int(r * 0.9)
			var tw := UiStyle.font(800).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_text(s, Vector2(c.x + step / 2 - tw / 2, c.y + fs * 0.35), fs, INK.lightened(0.3), 800)


func _kind_of(id: String) -> String:
	if Glyphs.FACE[set_name].has(id):
		return "BUTTON"
	if id in ["LT", "RT"]:
		return "TRIGGER"
	if id in ["LB", "RB"]:
		return "BUMPER"
	return "BUTTON"


static func _arrow_tag(dir: Vector2) -> String:
	var a := wrapf(atan2(dir.y, dir.x), 0.0, TAU)
	return ["→", "↗", "↑", "↖", "←", "↙", "↓", "↘"][int(round(a / (TAU / 8.0))) % 8]


func _text(text: String, pos: Vector2, font_size: int, col: Color, weight: int) -> void:
	draw_string(UiStyle.font(weight), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _text_centered(text: String, center: Vector2, font_size: int, col: Color, weight: int, max_width: float) -> void:
	var font := UiStyle.font(weight)
	var fs := font_size
	while fs > 12 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_width:
		fs -= 2
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, center + Vector2(-tw / 2, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
