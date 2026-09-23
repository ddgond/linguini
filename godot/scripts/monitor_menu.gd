class_name MonitorMenu
extends Control
## The UI shown on the room monitor, styled as the streamer's own cosy desktop:
## a wallpaper, a window holding the current page (pick a host, pair, choose
## an app, the in-stream menu), and a taskbar with the Linguini logo, whether
## we're live, the room's mood and a clock. Drives MoonlightClient's host
## requests and follows its signals. Rendered into a SubViewport and textured
## onto the monitor panel.
##
## While the fish swims without a stream, the monitor idles on the desktop
## with a note that cards light up but send nothing (set_idle).

signal swim_requested
signal resume_requested
signal edit_requested
signal tracking_changed(enabled: bool, style: int)

const FONT_SIZE := 26

var client: Object

var _window: PanelContainer
var _window_title: Label
var _window_subtitle: Label
var _page: VBoxContainer
var _status: Label
var _idle_note: PanelContainer
var _live_dot: Label
var _clock: Label
var _mood_label: Label
var _desktop: Control
var _pending := "" ## the host request this page is waiting on
var _host := ""
var _host_info := {}
var _apps: Array = []
var _app_name := ""
var _stage_label: Label
var _stats_label: Label
var _idle := false


func _ready() -> void:
	theme = UiStyle.make_theme(FONT_SIZE)
	_desktop = _Desktop.new()
	_desktop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_desktop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desktop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 84)
	add_child(margin)

	_window = PanelContainer.new()
	margin.add_child(_window)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	_window.add_child(outer)
	var title_bar := HBoxContainer.new()
	title_bar.add_theme_constant_override("separation", 14)
	outer.add_child(title_bar)
	var logo := _Logo.new()
	logo.custom_minimum_size = Vector2(52, 40)
	title_bar.add_child(logo)
	_window_title = _plain_label("", 38, UiStyle.TEXT, 800)
	title_bar.add_child(_window_title)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(fill)
	_window_subtitle = _plain_label("", 22, UiStyle.MUTED, 600)
	title_bar.add_child(_window_subtitle)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(1, 1, 1, 0.06)
	outer.add_child(rule)
	_page = VBoxContainer.new()
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 14)
	outer.add_child(_page)
	_status = _plain_label("", 22, UiStyle.DANGER, 600)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)

	_idle_note = PanelContainer.new()
	_idle_note.set_anchors_preset(Control.PRESET_CENTER)
	_idle_note.visible = false
	var note := VBoxContainer.new()
	_idle_note.add_child(note)
	note.add_child(_plain_label("Not streaming", 44, UiStyle.TEXT, 800))
	note.add_child(_plain_label("Cards light up but send nothing. Esc / %s opens the menu." % Glyphs.label("START"), 24, UiStyle.MUTED, 500))
	add_child(_idle_note)

	_taskbar()

	Mood.changed.connect(func(_m: String) -> void:
		theme = UiStyle.make_theme(FONT_SIZE)
		_desktop.queue_redraw())
	if client:
		client.host_ready.connect(_on_host_ready)
		client.paired.connect(_on_paired)
		client.apps_ready.connect(_on_apps_ready)
		client.request_failed.connect(_on_request_failed)
		client.stream_stage.connect(_on_stream_stage)
		client.stream_started.connect(_on_stream_started)
		client.stream_ended.connect(_on_stream_ended)
	show_home()


func _taskbar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -58
	var sb := UiStyle.box(Color(0.05, 0.055, 0.085, 0.92), 0, 10)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	bar.add_theme_stylebox_override("panel", sb)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	var logo := _Logo.new()
	logo.custom_minimum_size = Vector2(40, 30)
	row.add_child(logo)
	row.add_child(_plain_label("Linguini", 24, UiStyle.TEXT, 800))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	_live_dot = _plain_label("", 22, UiStyle.MUTED, 700)
	row.add_child(_live_dot)
	_mood_label = _plain_label("", 22, UiStyle.MUTED, 600)
	row.add_child(_mood_label)
	_clock = _plain_label("", 24, UiStyle.TEXT, 700)
	row.add_child(_clock)


## While idle the window is hidden and the desktop says we're not streaming.
func set_idle(value: bool) -> void:
	if value == _idle:
		return
	_idle = value
	_window.get_parent().visible = not value
	_idle_note.visible = value


func _process(_delta: float) -> void:
	var streaming: bool = client != null and client.is_streaming()
	if _stats_label and streaming:
		var size: Vector2i = client.get_video_size()
		_stats_label.text = "%s · %dx%d · %.0f fps" % [client.get_decoder_name(), size.x, size.y, client.get_video_fps()]
	if streaming:
		var vs: Vector2i = client.get_video_size()
		_live_dot.text = "●  LIVE  %dp%.0f" % [vs.y, client.get_video_fps()]
		_live_dot.add_theme_color_override("font_color", UiStyle.LIVE)
	else:
		_live_dot.text = "○  Offline"
		_live_dot.add_theme_color_override("font_color", UiStyle.MUTED)
	_mood_label.text = Mood.LABELS[Mood.NAMES.find(Mood.current)]
	_mood_label.add_theme_color_override("font_color", UiStyle.accent())
	var t := Time.get_time_dict_from_system()
	_clock.text = "%02d:%02d" % [t.hour, t.minute]
	if _idle_note.visible:
		_idle_note.position = (size - _idle_note.size) / 2 - Vector2(0, 20)


# --- pages ---

func show_home(message := "") -> void:
	_begin_page(message)
	_title("Linguini", "a Moonlight client for fish")

	if client == null:
		_label("The native Linguini library isn't loaded, so streaming is unavailable. Build it with `scons`.", 24, UiStyle.DANGER)
		_spacer()
		_button("Just swim", func() -> void: swim_requested.emit())
		_button("Edit tank", func() -> void: edit_requested.emit())
		_button("Quit", func() -> void: get_tree().quit())
		_focus_first()
		return

	var hosts: PackedStringArray = Settings.hosts()
	if hosts.is_empty():
		_label("No hosts yet. Add your Sunshine or GeForce Experience PC:", 24, UiStyle.MUTED)
	for address in hosts:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_page.add_child(row)
		var connect_button := _button("🖥  " + address, _connect.bind(address), row)
		connect_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		connect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button("Remove", func() -> void:
			Settings.remove_host(address)
			show_home(), row)

	var add_row := HBoxContainer.new()
	_page.add_child(add_row)
	var field := LineEdit.new()
	field.placeholder_text = "Host IP address or name"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(field)
	var add := func() -> void:
		var address := field.text.strip_edges()
		if address != "":
			Settings.add_host(address)
			_connect(address)
	field.text_submitted.connect(func(_t: String) -> void: add.call())
	_button("Add & connect", add, add_row)

	_spacer()
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	_page.add_child(actions)
	for entry in [["Just swim", func() -> void: swim_requested.emit()],
			["Edit tank", func() -> void: edit_requested.emit()],
			["Quit", func() -> void: get_tree().quit()]]:
		_button(entry[0], entry[1], actions).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tracking_row()
	_controls_help()
	_focus_first()


func show_in_stream() -> void:
	_begin_page()
	_title("Streaming", _app_name)
	_stats_label = _label("", 22, UiStyle.MUTED)
	_button("Resume", func() -> void: resume_requested.emit())
	_button("Edit tank", func() -> void: edit_requested.emit())
	_tracking_row()
	_button("Disconnect", func() -> void: client.stop_stream(false))
	_button("Quit game and disconnect", func() -> void: client.stop_stream(true))
	_spacer()
	_controls_help()
	_focus_first()


func _show_connecting(text: String) -> void:
	_begin_page()
	_title(_host, "")
	_label(text, 30, Color.WHITE)
	_spacer()
	_button("Back", _cancel)
	_focus_first()


func _show_pairing(pin: String) -> void:
	_begin_page()
	_title("Pair with " + _host, "")
	_label("Enter this PIN on the host:", 28, Color.WHITE)
	var big := _label(pin, 120, UiStyle.accent())
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("Sunshine: open https://%s:47990 and go to the PIN page.\nGeForce Experience shows a PIN prompt on the host." % _host, 22, UiStyle.MUTED)
	_spacer()
	_button("Back", _cancel)
	_focus_first()


func _show_apps(message := "") -> void:
	_begin_page(message)
	_title(_host, "Choose something to play")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_page.add_child(grid)
	# A host with a session already running resumes it whatever app is chosen.
	var running: int = _host_info.get("current_game", 0)
	for app: Dictionary in _apps:
		var title: String = app.name + ("  (running)" if app.id == running else "")
		var b := _button(title, _launch.bind(app), grid)
		b.icon = _app_icon(app.name)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(360, 64)
		b.clip_text = true
		b.disabled = running != 0 and app.id != running

	var settings := HBoxContainer.new()
	settings.add_theme_constant_override("separation", 12)
	_page.add_child(settings)
	var labels: Array = Settings.RESOLUTIONS.map(func(r: Vector2i) -> String: return "%dp" % r.y)
	_option(settings, labels, Settings.RESOLUTIONS, "resolution", Settings.RESOLUTIONS[0])
	_option(settings, Settings.FRAME_RATES.map(func(f: int) -> String: return "%d fps" % f), Settings.FRAME_RATES, "fps", 60)
	_option(settings, Settings.BITRATES_KBPS.map(func(b: int) -> String: return "%d Mbps" % (b / 1000)), Settings.BITRATES_KBPS, "bitrate_kbps", 10000)
	_option(settings, Settings.CODECS.map(func(c: String) -> String: return c.to_upper()), Settings.CODECS, "codec", "auto")
	_option(settings, ["Room speakers", "Stereo"], ["room", "stereo"], "audio", "room")

	_spacer()
	var row := HBoxContainer.new()
	_page.add_child(row)
	_button("Back", func() -> void: show_home(), row)
	if running != 0:
		_button("Quit running game", func() -> void:
			client.stop_stream(true)
			_connect(_host), row)
	_button("Unpair", func() -> void:
		client.unpair()
		show_home("Unpaired from " + _host), row)
	_focus_first()


func _show_launching() -> void:
	_begin_page()
	_title("Starting " + _app_name, _host)
	_stage_label = _label("Launching on host…", 28, Color.WHITE)
	_focus_first()


## "Tank cam" on/off plus its overlay style (the OBS-capturable window), the
## graphics quality preset and the room's mood.
func _tracking_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_page.add_child(row)
	var quality := OptionButton.new()
	var auto_name: String = Quality.NAMES[Quality.auto_level()]
	var values := ["auto", "low", "medium", "high"]
	for label in ["Graphics: Auto (%s)" % auto_name, "Graphics: Low", "Graphics: Medium", "Graphics: High"]:
		quality.add_item(label)
	quality.selected = maxi(values.find(Quality.setting), 0)
	quality.item_selected.connect(func(i: int) -> void: Quality.set_setting(values[i]))
	row.add_child(quality)
	var mood := OptionButton.new()
	mood.name = "MoodPicker"
	for label: String in Mood.LABELS:
		mood.add_item("Mood: " + label)
	mood.selected = Mood.NAMES.find(Mood.current)
	mood.item_selected.connect(func(i: int) -> void: Mood.set_mood(Mood.NAMES[i]))
	row.add_child(mood)
	var glyphs := OptionButton.new()
	glyphs.name = "GlyphPicker"
	var glyph_values: Array = ["auto"] + Glyphs.SETS
	glyphs.add_item("Buttons: Auto (%s)" % Glyphs.SET_LABELS[Glyphs.SETS.find(Glyphs.detected())])
	for label: String in Glyphs.SET_LABELS:
		glyphs.add_item("Buttons: " + label)
	glyphs.selected = maxi(glyph_values.find(Glyphs.setting), 0)
	glyphs.item_selected.connect(func(i: int) -> void:
		Glyphs.set_setting(glyph_values[i])
		_refresh_help())
	row.add_child(glyphs)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_page.add_child(row)
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = Settings.tracking_enabled()
	toggle.text = "Tank cam window: " + ("on" if toggle.button_pressed else "off")
	row.add_child(toggle)
	var style := OptionButton.new()
	for n in TrackingCam.STYLE_NAMES:
		style.add_item(n)
	style.selected = Settings.tracking_style()
	row.add_child(style)
	var apply := func() -> void:
		toggle.text = "Tank cam window: " + ("on" if toggle.button_pressed else "off")
		Settings.set_tracking(toggle.button_pressed, style.selected)
		tracking_changed.emit(toggle.button_pressed, style.selected)
	toggle.toggled.connect(func(_on: bool) -> void: apply.call())
	style.item_selected.connect(func(_i: int) -> void: apply.call())


# --- actions ---

func _connect(address: String) -> void:
	_host = address
	_pending = "connect"
	_show_connecting("Connecting…")
	client.connect_host(address)


func _launch(app: Dictionary) -> void:
	_app_name = app.name
	_pending = "launch"
	_show_launching()
	client.start_stream(app.id, Settings.stream_options())


func _cancel() -> void:
	# libgamestream requests can't be aborted; just stop listening for this one.
	_pending = ""
	show_home()


# --- client signals ---

func _on_host_ready(info: Dictionary) -> void:
	if _pending != "connect":
		return
	_host_info = info
	if info.paired:
		_pending = "apps"
		_show_connecting("Loading apps…")
		client.fetch_apps()
	else:
		_pending = "pair"
		var pin := "%04d" % randi_range(0, 9999)
		_show_pairing(pin)
		client.pair(pin)


func _on_paired() -> void:
	if _pending != "pair":
		return
	_pending = "apps"
	_show_connecting("Paired! Loading apps…")
	client.fetch_apps()


func _on_apps_ready(apps: Array) -> void:
	if _pending != "apps":
		return
	_pending = ""
	_apps = apps
	_show_apps()


func _on_request_failed(request: String, message: String) -> void:
	if request == "launch" and _pending == "launch":
		_pending = ""
		_show_apps("Couldn't start %s: %s" % [_app_name, message])
	elif request == _pending:
		_pending = ""
		show_home("%s: %s" % [_host, message])
	elif request == "quit":
		_status.text = "Couldn't quit the game: " + message


func _on_stream_stage(stage: String) -> void:
	if _stage_label:
		_stage_label.text = "Starting " + stage.to_lower() + "…"


func _on_stream_started() -> void:
	_pending = ""
	show_in_stream()


func _on_stream_ended(error_code: int, message: String) -> void:
	_stats_label = null
	_show_apps("" if error_code == 0 else message)


# --- building blocks ---

func _begin_page(message := "") -> void:
	_stage_label = null
	_stats_label = null
	for child in _page.get_children():
		child.queue_free()
	_status.text = message


func _title(text: String, subtitle: String) -> void:
	_window_title.text = text
	_window_subtitle.text = subtitle


## The controls, named in the current button glyph set.
func _controls_help() -> void:
	var help := _label(_help_text(), 18, UiStyle.MUTED)
	help.name = "ControlsHelp"


func _refresh_help() -> void:
	var help := _page.get_node_or_null("ControlsHelp") as Label
	if help:
		help.text = _help_text()


func _help_text() -> String:
	var g := func(id: String) -> String: return Glyphs.label(id)
	return ("Swim, turn  WASD / left stick      Rise / sink  Space, C / %s, %s      Dart  Shift / %s\n" +
		"Look  mouse / right stick      Watch the monitor  hold right mouse / %s      Menu  Esc / %s      Edit tank  F2      Tank cam  F4") % [
		g.call("RB"), g.call("LB"), g.call("A"), g.call("LT"), g.call("START")]


## A little square icon for an app, coloured from its name.
func _app_icon(app_name: String) -> Texture2D:
	var img := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	var hue := float(hash(app_name) % 360) / 360.0
	img.fill(Color.from_hsv(hue, 0.45, 0.7))
	return ImageTexture.create_from_image(img)


func _plain_label(text: String, font_size: int, color: Color, weight := 500) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiStyle.font(weight))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(label)
	return label


func _button(text: String, callback: Callable, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	(parent if parent else _page).add_child(b)
	return b


func _option(parent: Control, labels: Array, values: Array, key: String, default: Variant) -> void:
	var opt := OptionButton.new()
	for l in labels:
		opt.add_item(l)
	var current: Variant = Settings.get_stream(key, default)
	opt.selected = maxi(values.find(current), 0)
	opt.item_selected.connect(func(i: int) -> void: Settings.set_stream(key, values[i]))
	parent.add_child(opt)


func _spacer() -> void:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_child(s)


func _focus_first() -> void:
	(func() -> void:
		for node in _page.find_children("*", "BaseButton", true, false):
			if node.is_visible_in_tree():
				node.grab_focus()
				return
	).call_deferred()


## The wallpaper: a soft gradient in the mood's accent, with gentle waves
## and a big faint fish.
class _Desktop:
	extends Control

	func _draw() -> void:
		var a := UiStyle.accent()
		var top := UiStyle.BG.lerp(a, 0.18)
		var bottom := UiStyle.BG.darkened(0.3)
		var steps := 24
		for i in steps:
			var t := float(i) / steps
			draw_rect(Rect2(0, size.y * t, size.x, size.y / steps + 1), top.lerp(bottom, t))
		for k in 3:
			var pts := PackedVector2Array()
			var base := size.y * (0.62 + k * 0.1)
			for x in range(0, int(size.x) + 40, 40):
				pts.append(Vector2(x, base + sin(x * 0.006 + k * 1.7) * 26.0))
			pts.append(Vector2(size.x, size.y))
			pts.append(Vector2(0, size.y))
			draw_colored_polygon(pts, Color(a, 0.05 + k * 0.03))
		_Logo.draw_fish(self, Vector2(size.x * 0.76, size.y * 0.42), size.y * 0.3, Color(a, 0.08))


## The Linguini logo: a round little goldfish.
class _Logo:
	extends Control

	func _draw() -> void:
		draw_fish(self, size / 2, size.y * 0.5, Color(1.0, 0.58, 0.2))

	static func draw_fish(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
		var body := PackedVector2Array()
		for i in 32:
			var t := TAU * i / 32.0
			body.append(c + Vector2(cos(t) * r * 0.8, sin(t) * r * 0.62))
		ci.draw_colored_polygon(body, col)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.62, 0), c + Vector2(-r * 1.25, -r * 0.55),
			c + Vector2(-r * 1.05, 0), c + Vector2(-r * 1.25, r * 0.55)]), col)
		if col.a > 0.5:
			ci.draw_circle(c + Vector2(r * 0.38, -r * 0.12), r * 0.14, Color.WHITE)
			ci.draw_circle(c + Vector2(r * 0.42, -r * 0.12), r * 0.07, Color(0.1, 0.1, 0.15))
