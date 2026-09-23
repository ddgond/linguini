class_name UiStyle
extends RefCounted
## Linguini's look for its 2D UI (the monitor's "streamer OS" and the tank
## editor): fonts, colours and the Theme built from them.
##
## Fonts (bundled, SIL Open Font License, see fonts/*-OFL.txt):
##   Nunito          everything, set as the project's default font
##   JetBrains Mono  the tank cam's readouts

const NUNITO := preload("res://fonts/Nunito.ttf")
const MONO := preload("res://fonts/JetBrainsMono.ttf")

const BG := Color(0.07, 0.08, 0.12)
const PANEL := Color(0.1, 0.11, 0.16, 0.94)
const RAISED := Color(0.16, 0.17, 0.24)
const RAISED_HOVER := Color(0.22, 0.24, 0.33)
const TEXT := Color(0.93, 0.93, 0.96)
const MUTED := Color(0.66, 0.69, 0.78)
const DANGER := Color(1.0, 0.55, 0.45)
const LIVE := Color(1.0, 0.3, 0.3)

## Each mood's accent, used for focus rings, the logo and highlights.
const ACCENTS := {
	"night": Color(0.72, 0.52, 1.0),
	"rainy": Color(0.45, 0.75, 1.0),
	"golden": Color(1.0, 0.64, 0.3),
}

static var _fonts := {}


## Nunito (or JetBrains Mono) at a weight: 400 regular, 700 bold, 800 extra bold.
static func font(weight := 400, mono := false) -> Font:
	var key := "%s%d" % ["mono" if mono else "sans", weight]
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = MONO if mono else NUNITO
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[key] = f
	return _fonts[key]


static func accent(mood := "") -> Color:
	return ACCENTS.get(mood if mood != "" else Mood.current, ACCENTS.night)


static func box(color: Color, radius := 14, margin := 12.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


## The Theme for a UI drawn at `font_size` (the monitor uses 26, the editor 16).
static func make_theme(font_size: int, mood := "") -> Theme:
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = font_size
	var a := accent(mood)
	var pad := font_size * 0.45
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 20, font_size * 1.1))
	t.set_stylebox("panel", "Panel", box(PANEL, 20, font_size * 1.1))
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, box(RAISED, 12, pad))
		t.set_stylebox("hover", type, box(RAISED_HOVER, 12, pad))
		t.set_stylebox("pressed", type, box(a.darkened(0.15), 12, pad))
		t.set_stylebox("hover_pressed", type, box(a, 12, pad))
		t.set_stylebox("disabled", type, box(RAISED.darkened(0.3), 12, pad))
		var focus := box(Color.TRANSPARENT, 12, pad)
		focus.draw_center = false
		focus.border_color = a
		focus.set_border_width_all(3)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color(0.08, 0.06, 0.12))
		t.set_color("font_hover_pressed_color", type, Color(0.08, 0.06, 0.12))
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, MUTED.darkened(0.3))
		t.set_font("font", type, font(700))
	var field := box(Color(0.05, 0.06, 0.09), 12, pad)
	field.border_color = RAISED_HOVER
	field.set_border_width_all(2)
	t.set_stylebox("normal", "LineEdit", field)
	var field_focus: StyleBoxFlat = field.duplicate()
	field_focus.border_color = a
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED.darkened(0.2))
	t.set_color("caret_color", "LineEdit", a)
	t.set_color("font_color", "Label", TEXT)
	var popup := box(Color(0.12, 0.13, 0.19), 12, 6)
	popup.border_color = RAISED_HOVER
	popup.set_border_width_all(1)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(RAISED_HOVER, 8, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font("font", "PopupMenu", font(600))
	t.set_font_size("font_size", "PopupMenu", font_size)
	var tip := box(Color(0.05, 0.05, 0.08, 0.95), 8, 8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t
