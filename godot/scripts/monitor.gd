class_name Monitor
extends Node
## Drives the room monitor's screen: shows the stream from MoonlightClient and
## renders the monitor's menu UI (a SubViewport) onto the same panel. Mouse
## input is ray-cast from the active camera onto the panel and forwarded to the
## menu; keys and gamepad buttons are forwarded as-is.

const MENU_RESOLUTION := Vector2i(1280, 720)

var screen: MeshInstance3D
var screen_size: Vector2
var client: Object
var menu: Control
var viewport: SubViewport
var menu_visible := true
## Whether the stream should be on screen (false once a session ends).
var show_video := false

var _material: ShaderMaterial
var _menu_fade := 1.0


func setup(p_screen: MeshInstance3D, p_size: Vector2, p_client: Object, p_menu: Control) -> void:
	screen = p_screen
	screen_size = p_size
	client = p_client
	menu = p_menu

	viewport = SubViewport.new()
	viewport.size = MENU_RESOLUTION
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	add_child(viewport)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(menu)

	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/monitor_screen.gdshader")
	_material.set_shader_parameter("menu_tex", viewport.get_texture())
	_material.set_shader_parameter("panel_size", screen_size)
	if client:
		_material.set_shader_parameter("y_tex", client.get_y_texture())
		_material.set_shader_parameter("uv_tex", client.get_uv_texture())
	screen.material_override = _material


func _process(delta: float) -> void:
	_menu_fade = move_toward(_menu_fade, 1.0 if menu_visible else 0.0, delta / 0.25)
	_material.set_shader_parameter("menu_opacity", _menu_fade)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _menu_fade > 0.0 else SubViewport.UPDATE_DISABLED
	if client:
		var video: bool = show_video and client.has_video()
		_material.set_shader_parameter("has_video", video)
		if video:
			_material.set_shader_parameter("video_size", Vector2(client.get_video_size()))
			_material.set_shader_parameter("bt709", client.is_bt709())
			_material.set_shader_parameter("full_range", client.is_full_range())


## Forwards an input event to the menu. Mouse events are mapped through
## `camera` onto the panel; returns true if the event landed on the menu.
func forward_input(event: InputEvent, camera: Camera3D) -> bool:
	if not menu_visible:
		return false
	if event is InputEventMouse:
		var uv: Variant = _panel_uv(camera, event.position)
		if uv == null:
			return false
		var ev: InputEventMouse = event.duplicate()
		ev.position = uv * Vector2(MENU_RESOLUTION)
		ev.global_position = ev.position
		viewport.push_input(ev)
		return true
	viewport.push_input(event)
	return true


func _panel_uv(camera: Camera3D, mouse: Vector2) -> Variant:
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var plane := Plane(screen.global_basis.z, screen.global_position)
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit == null:
		return null
	var local: Vector3 = screen.to_local(hit)
	var uv := Vector2(local.x / screen_size.x + 0.5, 0.5 - local.y / screen_size.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return null
	return uv
