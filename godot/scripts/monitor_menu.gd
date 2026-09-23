class_name MonitorMenu
extends Control
## The UI shown on the room monitor: pick a host, pair, choose an app, and the
## in-stream menu. Drives MoonlightClient's host requests and follows its
## signals. Rendered into a SubViewport and textured onto the monitor panel.

signal swim_requested
signal resume_requested

const CONTROLS_HELP := "Swim, turn  WASD / left stick      Rise / sink  Space, C / RB, LB      Dart  Shift / A\nLook  mouse / right stick      Watch the monitor  hold right mouse / LT      Menu  Esc / Start"

var client: Object

var _panel: PanelContainer
var _page: VBoxContainer
var _status: Label
var _pending := "" ## the host request this page is waiting on
var _host := ""
var _host_info := {}
var _apps: Array = []
var _app_name := ""
var _stage_label: Label
var _stats_label: Label


func _ready() -> void:
	theme = _make_theme()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.06, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)

	_panel = PanelContainer.new()
	margin.add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	_panel.add_child(outer)
	_page = VBoxContainer.new()
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 14)
	outer.add_child(_page)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)

	if client:
		client.host_ready.connect(_on_host_ready)
		client.paired.connect(_on_paired)
		client.apps_ready.connect(_on_apps_ready)
		client.request_failed.connect(_on_request_failed)
		client.stream_stage.connect(_on_stream_stage)
		client.stream_started.connect(_on_stream_started)
		client.stream_ended.connect(_on_stream_ended)
	show_home()


func _process(_delta: float) -> void:
	if _stats_label and client and client.is_streaming():
		var size: Vector2i = client.get_video_size()
		_stats_label.text = "%s · %dx%d · %.0f fps" % [client.get_decoder_name(), size.x, size.y, client.get_video_fps()]


# --- pages ---

func show_home(message := "") -> void:
	_begin_page(message)
	_title("LINGUINI", "a Moonlight client for fish")

	if client == null:
		_label("The native Linguini library isn't loaded, so streaming is unavailable. Build it with `scons`.", 24, Color(1.0, 0.55, 0.45))
		_spacer()
		_button("Just swim", func() -> void: swim_requested.emit())
		_focus_first()
		return

	var hosts: PackedStringArray = Settings.hosts()
	if hosts.is_empty():
		_label("No hosts yet. Add your Sunshine or GeForce Experience PC:", 24, Color(0.75, 0.8, 0.9))
	for address in hosts:
		var row := HBoxContainer.new()
		_page.add_child(row)
		var connect_button := _button(address, _connect.bind(address), row)
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
	_button("Just swim", func() -> void: swim_requested.emit())
	_label(CONTROLS_HELP, 18, Color(0.65, 0.7, 0.8))
	_focus_first()


func show_in_stream() -> void:
	_begin_page()
	_title("Streaming", _app_name)
	_stats_label = _label("", 22, Color(0.7, 0.85, 0.9))
	_button("Resume", func() -> void: resume_requested.emit())
	_button("Disconnect", func() -> void: client.stop_stream(false))
	_button("Quit game and disconnect", func() -> void: client.stop_stream(true))
	_spacer()
	_label(CONTROLS_HELP, 18, Color(0.65, 0.7, 0.8))
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
	var big := _label(pin, 120, Color(1.0, 0.8, 0.3))
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("Sunshine: open https://%s:47990 and go to the PIN page.\nGeForce Experience shows a PIN prompt on the host." % _host, 22, Color(0.75, 0.8, 0.9))
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
	_label(text, 56, Color(1.0, 0.6, 0.25))
	if subtitle != "":
		_label(subtitle, 26, Color(0.7, 0.75, 0.85))


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


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 28
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.07, 0.11, 0.92)
	panel.set_corner_radius_all(18)
	panel.set_content_margin_all(32)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(12)
		sb.bg_color = {
			"normal": Color(0.16, 0.18, 0.26),
			"hover": Color(0.24, 0.28, 0.4),
			"pressed": Color(1.0, 0.5, 0.15),
			"focus": Color(0, 0, 0, 0),
		}[state]
		if state == "focus":
			sb.border_color = Color(1.0, 0.6, 0.25)
			sb.set_border_width_all(3)
			sb.draw_center = false
		t.set_stylebox(state, "Button", sb)
		t.set_stylebox(state, "OptionButton", sb)
	return t
