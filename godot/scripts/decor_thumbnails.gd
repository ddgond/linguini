class_name DecorThumbnails
extends RefCounted
## Little pictures of each decor piece for the tank editor's palette, rendered
## once each in an offscreen world of its own (a SubViewport with a camera,
## a key light and the piece in its first colour).

const SIZE := 96

static var _cache := {}
static var _waiting := {}


## Calls `done(texture)` with the thumbnail for decor `id`.
static func request(id: String, host: Node, done: Callable) -> void:
	if _cache.has(id):
		done.call(_cache[id])
		return
	if _waiting.has(id):
		_waiting[id].append(done)
		return
	_waiting[id] = [done]
	_render(id, host)


static func _render(id: String, host: Node) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var world := WorldEnvironment.new()
	world.environment = env
	vp.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.4
	vp.add_child(sun)
	var piece := DecorPiece.new(id)
	piece.quiet = true
	vp.add_child(piece)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	host.add_child(vp)
	var tree := host.get_tree()
	await tree.process_frame
	if not is_instance_valid(vp):
		# The editor went away mid-render; a later request will try again.
		_waiting.erase(id)
		return
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.visible:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var radius := maxf(box.size.length() * 0.5, 0.01)
	var center := box.get_center()
	var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * 1.05
	cam.look_at_from_position(center + Vector3(0.45, 0.4, 1.0).normalized() * dist, center)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		_waiting.erase(id)
		return
	var img := vp.get_texture().get_image()
	var texture: Texture2D = null
	if img != null and not img.is_empty():
		texture = ImageTexture.create_from_image(img)
	else:
		var blank := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		texture = ImageTexture.create_from_image(blank)
	vp.queue_free()
	_cache[id] = texture
	for done: Callable in _waiting.get(id, []):
		if done.is_valid():
			done.call(texture)
	_waiting.erase(id)
