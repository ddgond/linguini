class_name Stepper
extends PanelContainer
## A setting's row on the monitor: its label, then ◀ value ▶. Left and right
## (or the arrows, clicked) step through the options. Used on the Settings
## page, where it takes focus like any control, and in each player's column
## on the Controls page, whose cursors light it instead (`lit`).
##
## Speaks OptionButton's language (item_count, selected, select(),
## item_selected), so it can stand in for one.

signal item_selected(index: int)

var options: Array = []
var selected := 0
var item_count: int:
	get:
		return options.size()
## Lit by a Controls page cursor rather than by focus.
var lit := false:
	set(value):
		lit = value
		_restyle()
## The highlight's colour.
var accent := Color(0.55, 0.7, 1.0)
## Whether the options wrap round at the ends.
var wrap := true

var _value: Label
var _label: Label


func _init(label: String, p_options: Array, p_selected := 0, label_size := 22, label_width := 170.0) -> void:
	options = p_options
	selected = clampi(p_selected, 0, maxi(options.size() - 1, 0))
	focus_mode = Control.FOCUS_ALL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	_label = Label.new()
	_label.text = label
	_label.add_theme_font_override("font", UiStyle.font(600))
	_label.add_theme_font_size_override("font_size", label_size)
	_label.add_theme_color_override("font_color", UiStyle.MUTED)
	_label.custom_minimum_size.x = label_width
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_label)
	_arrow(row, "◀", -1, label_size)
	_value = Label.new()
	_value.add_theme_font_override("font", UiStyle.font(700))
	_value.add_theme_font_size_override("font_size", label_size)
	_value.add_theme_color_override("font_color", UiStyle.TEXT)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.custom_minimum_size.x = label_width * 0.75
	row.add_child(_value)
	_arrow(row, "▶", 1, label_size)
	_show()
	_restyle()
	focus_entered.connect(_restyle)
	focus_exited.connect(_restyle)


func select(index: int) -> void:
	selected = clampi(index, 0, maxi(options.size() - 1, 0))
	_show()


## One step left (-1) or right (+1), as the player asked for it.
func step(dir: int) -> void:
	if options.is_empty():
		return
	var i := selected + dir
	i = wrapi(i, 0, options.size()) if wrap else clampi(i, 0, options.size() - 1)
	if i == selected:
		return
	selected = i
	_show()
	item_selected.emit(selected)


func set_options(p_options: Array, p_selected: int) -> void:
	options = p_options
	select(p_selected)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
		step(1)
		accept_event()


func _arrow(row: HBoxContainer, glyph: String, dir: int, font_size: int) -> void:
	var b := Button.new()
	b.text = glyph
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(font_size * 0.85))
	b.pressed.connect(func() -> void:
		if focus_mode != Control.FOCUS_NONE:
			grab_focus()
		step(dir))
	row.add_child(b)


func _show() -> void:
	if _value:
		_value.text = str(options[selected]) if selected < options.size() else ""


func _restyle() -> void:
	var on := lit or has_focus()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	if on:
		sb.bg_color = Color(accent, 0.22)
		sb.border_color = accent
		sb.set_border_width_all(2)
	else:
		sb.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("panel", sb)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
